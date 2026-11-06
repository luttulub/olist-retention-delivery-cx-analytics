/*
olist 판매 성과 분석 및 tableau 데이터 추출

목적:
- 월별 상품 gmv, 주문 수, aov, 전월 대비 성장률을 분석한다.
- 상품 카테고리별 gmv와 월별 기여도를 비교한다.

분석 기준:
- 주문 상태가 delivered인 주문만 포함한다.
- 상품 gmv = items.price 합계 (배송비 제외, 회계상 매출 아님)
- total_payment = 주문별 payments.payment_value 합계 (상품 gmv와 구분)
- aov = 결제 정보가 있는 delivered 주문의 주문별 결제금액 평균
- 분석 기간은 우선 2017-01-01 ~ 2018-08-31로 설정한다.
  기간 양끝의 불완전한 월 여부를 1번 쿼리로 확인한 뒤 확정한다.

실행 순서:
1. 데이터 기간 확인
2. 주문 단위 판매 마트 생성
3. 월별 kpi view 생성
4. 카테고리별 kpi view 생성
5. 검증 및 tableau 데이터 추출
*/


-- =========================================================
-- 1. 분석 기간 및 월별 완료 주문 수 확인
-- =========================================================

select
	date_trunc('month', nullif(trim(purchase_timestamp), '')::timestamp)::date as order_month,
	count(*) as total_order_cnt,
	count(*) filter (where order_status = 'delivered') as delivered_order_cnt
from order_level_mart
where nullif(trim(purchase_timestamp), '') is not null
group by 1
order by 1;

/*
- 2017-01 ~ 2018-08을 비교 기간으로 사용
*/


-- =========================================================
-- 2. 주문 단위 판매 성과 데이터 마트
-- 한 주문 = 한 행 유지
-- =========================================================

create or replace view sales_order_mart as

with item_summary as (
	select
		order_id,
		sum(price::numeric) as product_gmv,
		count(*) as item_count
	from items
	group by order_id
),

order_base as (
	select
		o.order_id,
		o.customer_unique_id,
		date_trunc('month', nullif(trim(o.purchase_timestamp), '')::timestamp)::date as order_month,
		o.payment_total,
		i.product_gmv,
		i.item_count
	from order_level_mart o
		left join item_summary i
			on o.order_id = i.order_id
	where o.order_status = 'delivered'
		and nullif(trim(o.purchase_timestamp), '')::timestamp >= timestamp '2017-01-01'
		and nullif(trim(o.purchase_timestamp), '')::timestamp < timestamp '2018-09-01'
)
select *
from order_base;


-- 주문 단위가 유지되는지 검증
select
	count(*) as row_cnt,
	count(distinct order_id) as unique_order_cnt,
	count(*) filter (where product_gmv is null) as missing_product_gmv_cnt,
	count(*) filter (where payment_total is null) as missing_payment_cnt
from sales_order_mart;


-- =========================================================
-- 3. 월별 성과 kpi 및 전월 대비 성장률
-- =========================================================

create or replace view sales_monthly_kpi as

with monthly_summary as (
	select
		order_month,
		count(*) as delivered_orders,
		count(product_gmv) as orders_with_product_gmv,
		count(payment_total) as orders_with_payment,
		round(sum(product_gmv), 2) as product_gmv,
		round(sum(payment_total)::numeric, 2) as total_payment,
		round(avg(payment_total)::numeric, 2) as aov
	from sales_order_mart
	group by order_month
),

monthly_growth as (
	select
		*,
		lag(product_gmv) over (order by order_month) as previous_month_gmv
	from monthly_summary
)

select
	order_month,
	delivered_orders,
	orders_with_product_gmv,
	orders_with_payment,
	product_gmv,
	total_payment,
	aov,
	previous_month_gmv,
	round((product_gmv - previous_month_gmv) / nullif(previous_month_gmv, 0) * 100, 2) as mom_gmv_growth_pct
from monthly_growth;

select
    order_month,
    delivered_orders,
    product_gmv,
    total_payment,
    aov,
    previous_month_gmv,
    mom_gmv_growth_pct
from sales_monthly_kpi
order by order_month;


-- =========================================================
-- 4. 월별 상품 카테고리 성과 및 gmv 기여도
-- =========================================================

create or replace view sales_category_kpi as

with category_order_summary as (
	select
		o.order_month,
		coalesce(
			nullif(trim(c.product_category_name_english), ''),
			'unknown_category'
		) as category_name,
		i.order_id,
		count(*) as item_count,
		sum(i.price::numeric) as category_gmv
	from sales_order_mart o
		inner join items i
			on o.order_id = i.order_id
		left join products p
			on i.product_id = p.product_id
		left join category c
			on p.product_category_name = c.product_category_name
	group by 1, 2, 3
),

category_monthly as (
	select
		order_month,
		category_name,
		count(*) as orders_with_category,
		sum(item_count) as items_sold,
		round(sum(category_gmv), 2) as category_gmv
	from category_order_summary
	group by order_month, category_name
)

select
	order_month,
	category_name,
	orders_with_category,
	items_sold,
	category_gmv,
	round(
		category_gmv / nullif(sum(category_gmv) over (partition by order_month), 0) * 100,
		2
	) as monthly_gmv_share_pct
from category_monthly;


select *
from sales_category_kpi
order by order_month, category_gmv desc;


-- =========================================================
-- 5. 판매 성과 결과 검증
-- =========================================================

-- 월별 상품 gmv 합계와 카테고리별 상품 gmv 합계 비교
select
	m.order_month,
	m.product_gmv as order_based_gmv,
	c.category_based_gmv,
	round(m.product_gmv - c.category_based_gmv, 2) as difference
from sales_monthly_kpi m
	left join (
		select
			order_month,
			round(sum(category_gmv), 2) as category_based_gmv
		from sales_category_kpi
		group by order_month
	) c
		on m.order_month = c.order_month
order by m.order_month;


-- =========================================================
-- 6. 전체 기간 gmv 상위 10개 카테고리 확인
-- =========================================================

select
    category_name,
    round(sum(category_gmv), 2) as total_gmv,
    round(sum(category_gmv)/ nullif(sum(sum(category_gmv)) over (), 0) * 100, 2) as gmv_share_pct
from sales_category_kpi
group by category_name
order by total_gmv desc
limit 10;


-- =========================================================
-- 7. tableau용 결과 데이터 추출
-- 동일 sql 파일에서 결과 세트만 각각 csv로 저장
-- =========================================================

-- 7-1. 월별 추이 및 상단 kpi 카드용
select *
from sales_monthly_kpi
order by order_month;


-- 7-2. 상품 카테고리별 gmv 기여도용
select *
from sales_category_kpi
order by order_month, category_gmv desc;