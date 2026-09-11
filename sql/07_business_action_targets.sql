/*
olist 비즈니스 액션 타깃 분석

목적:
- retention, cx 분석과 python 검증 결과를 기반으로 우선 액션 대상을 선정한다.
- q3, q4 고객을 retention target pool로 정의하고 category, cohort를 함께 고려한다.
- 4일 이상 배송 지연 고객을 cx target으로 정의하고 cohort별 성과 차이를 확인한다.
- 최종 target 규모와 baseline kpi를 산출해 후속 a/b test 설계로 연결한다.
*/


-- =========================================================
-- 1. 비즈니스 액션 타깃 분석용 고객 데이터 구성
-- action_target_base
-- =========================================================

drop table if exists action_target_base;

create temporary table action_target_base as

with payment_thresholds as (
	select
		percentile_cont(0.25) within group (order by first_order_payment_total) as q1,
		percentile_cont(0.50) within group (order by first_order_payment_total) as median,
		percentile_cont(0.75) within group (order by first_order_payment_total) as q3
	from customer_behavior_mart
	where eligible_90d = 1 and first_order_payment_total is not null
),

first_order_category_base as (
	select c.customer_unique_id, c.first_order_id, i.order_item_id,
		nullif(trim(cat.product_category_name_english), '') as product_category_name_english
	from customer_behavior_mart c
		left join items i on c.first_order_id = i.order_id
		left join products p on i.product_id = p.product_id
		left join category cat on p.product_category_name = cat.product_category_name
),

first_order_category_summary as (
	select customer_unique_id, first_order_id,
		count(distinct product_category_name_english) as category_cnt,
		count(*) filter (where order_item_id is not null and product_category_name_english is null) as null_category_item_cnt,
		max(product_category_name_english) as single_category_name
	from first_order_category_base
	group by customer_unique_id, first_order_id
),

category_group_base as (
	select customer_unique_id,
		case
			when null_category_item_cnt > 0 then 'unknown_category'
			when category_cnt = 1 then single_category_name
			when category_cnt >= 2 then 'multi_category'
			else 'unknown_category'
		end as first_order_category
	from first_order_category_summary
)

select
	c.customer_unique_id, c.first_order_id, c.first_order_payment_total,
	case
		when c.first_order_payment_total is null then 'unknown'
		when c.first_order_payment_total <= t.q1 then 'q1'
		when c.first_order_payment_total <= t.median then 'q2'
		when c.first_order_payment_total <= t.q3 then 'q3'
		else 'q4'
	end as payment_group,
	c.eligible_90d, c.repurchase_90d, g.first_order_category,
	c.cohort_month, date_trunc('quarter', c.cohort_month)::date as cohort_quarter,
	c.first_order_delayed_flag,
	case
		when c.first_order_delayed_flag = 0 then 'normal'
		when c.first_order_delayed_flag = 1 then 'delayed'
		else 'unknown'
	end as delivery_group,
	o.delivery_delay_days, c.first_order_review_score,
	case
		when c.first_order_review_score is null then null
		when c.first_order_review_score < 3 then 1
		else 0
	end as low_review_flag
from customer_behavior_mart c
	left join order_level_mart o on c.first_order_id = o.order_id
	left join category_group_base g on c.customer_unique_id = g.customer_unique_id
	cross join payment_thresholds t;


-- 구조 확인
select
	count(*) as customer_cnt,
	count(distinct customer_unique_id) as distinct_customer_cnt,
	count(*) filter (where eligible_90d = 1) as eligible_90d_customer_cnt,
	count(*) filter (where repurchase_90d = 1) as repurchase_90d_customer_cnt,
	count(*) filter (where payment_group = 'unknown') as unknown_payment_customer_cnt,
	count(*) filter (where delivery_group = 'unknown') as unknown_delivery_customer_cnt,
	count(*) filter (where first_order_category = 'unknown_category') as unknown_category_customer_cnt,
	count(*) filter (where first_order_review_score is null) as no_review_customer_cnt
from action_target_base;

/*
확인 결과:
- 전체 고객 93,358명, 90일 관찰 가능 고객 75,387명, 90일 내 재구매 고객 1,716명으로 기존 retention 검증 결과와 일치했다.
- payment unknown 1명, delivery unknown 8명, category unknown 1,367명, review 결측 615명으로 기존 데이터 검증 결과와 일치했다.
*/


-- =========================================================
-- 2. retention target pool 확인
-- =========================================================

with payment_summary as (
	select
		payment_group,
		count(*) as customer_cnt,
		count(*) filter (where eligible_90d = 1) as eligible_90d_customer_cnt,
		count(*) filter (where repurchase_90d = 1) as repurchase_90d_customer_cnt,
		count(*) filter (where repurchase_90d = 1)::numeric
			/ nullif(count(*) filter (where eligible_90d = 1), 0) * 100 as repurchase_90d_rate
	from action_target_base
	where payment_group <> 'unknown'
	group by payment_group
),

q1_benchmark as (
	select repurchase_90d_rate as q1_repurchase_rate
	from payment_summary
	where payment_group = 'q1'
)

select
	p.payment_group, p.customer_cnt, p.eligible_90d_customer_cnt, p.repurchase_90d_customer_cnt,
	round(p.repurchase_90d_rate, 2) as repurchase_90d_rate,
	round(p.repurchase_90d_rate - q.q1_repurchase_rate, 2) as gap_pp_vs_q1
from payment_summary p
	cross join q1_benchmark q
order by
	case p.payment_group
		when 'q1' then 1
		when 'q2' then 2
		when 'q3' then 3
		when 'q4' then 4
	end;


-- q3, q4 retention target pool 규모 확인
select
	count(*) filter (where payment_group in ('q3', 'q4')) as target_customer_cnt,
	round(count(*) filter (where payment_group in ('q3', 'q4'))::numeric
		/ nullif(count(*) filter (where payment_group <> 'unknown'), 0) * 100, 2) as target_customer_rate,
	count(*) filter (where payment_group in ('q3', 'q4') and eligible_90d = 1) as eligible_90d_customer_cnt,
	count(*) filter (where payment_group in ('q3', 'q4') and repurchase_90d = 1) as repurchase_90d_customer_cnt,
	round(count(*) filter (where payment_group in ('q3', 'q4') and repurchase_90d = 1)::numeric
		/ nullif(count(*) filter (where payment_group in ('q3', 'q4') and eligible_90d = 1), 0) * 100, 2) as repurchase_90d_rate
from action_target_base;

/*
확인 결과:
- 90일 재구매율은 q1 2.46%, q2 2.41%, q3 2.16%, q4 2.07%로 q3, q4에서 상대적으로 낮았으며, q1 대비 각각 -0.30%p, -0.39%p의 gap이 확인됐다.
- python 회귀에서도 category와 cohort를 고려한 뒤 q3, q4의 낮은 재구매 odds가 유의하게 유지됐으므로, 두 그룹을 retention target pool로 사용한다.
- q3, q4 고객은 총 46,878명으로 전체의 50.21%이며, 이 중 90일 관찰 가능 고객 37,691명의 재구매율은 2.12%였다.
*/



-- =========================================================
-- 3. retention target의 category별 차이 확인
-- =========================================================

with stable_category as (
	select first_order_category
	from action_target_base
	where first_order_category not in ('unknown_category', 'multi_category')
	group by first_order_category
	having count(*) filter (where eligible_90d = 1) >= 1000
),

category_summary as (
	select
		first_order_category,
		count(*) as target_customer_cnt,
		count(*) filter (where eligible_90d = 1) as eligible_90d_customer_cnt,
		count(*) filter (where repurchase_90d = 1) as repurchase_90d_customer_cnt,
		count(*) filter (where repurchase_90d = 1)::numeric
			/ nullif(count(*) filter (where eligible_90d = 1), 0) * 100 as repurchase_90d_rate
	from action_target_base
	where payment_group in ('q3', 'q4')
		and first_order_category in (select first_order_category from stable_category)
	group by first_order_category
),

target_benchmark as (
	select count(*) filter (where repurchase_90d = 1)::numeric
		/ nullif(count(*) filter (where eligible_90d = 1), 0) * 100 as target_repurchase_rate
	from action_target_base
	where payment_group in ('q3', 'q4')
)

select
	c.first_order_category,
	c.target_customer_cnt,
	c.eligible_90d_customer_cnt,
	c.repurchase_90d_customer_cnt,
	round(c.repurchase_90d_rate, 2) as repurchase_90d_rate,
	round(c.repurchase_90d_rate - b.target_repurchase_rate, 2) as gap_pp_vs_target
from category_summary c
	cross join target_benchmark b
order by
	c.repurchase_90d_rate,
	c.eligible_90d_customer_cnt desc;
/*
확인 결과:
- q3, q4 고객의 90일 재구매율은 category별로 0.55%~4.20%까지 차이가 나타나, 전체 q3, q4 baseline 2.12% 안에서도 category별 retention 편차가 컸다.
- electronics, stationery, cool_stuff 등은 baseline보다 낮았고, furniture_decor, bed_bath_table, fashion_bags_accessories 등은 상대적으로 높은 재구매율을 보였다.
- 일부 category는 q3, q4 내 관찰 고객과 재구매 건수가 적어 단독 타깃 조건으로 사용하기보다, retention 우선순위와 개인화 context로 활용하는 것이 적절하다.
*/



-- =========================================================
-- 4. 배송 지연 강도별 cx 차이 확인
-- =========================================================

with delay_severity_base as (
	select
		case
			when delivery_delay_days <= 3 then '1-3d'
			when delivery_delay_days <= 7 then '4-7d'
			when delivery_delay_days <= 13 then '8-13d'
			else '14d plus'
		end as delay_group,
		first_order_review_score,
		low_review_flag
	from action_target_base
	where delivery_group = 'delayed' and delivery_delay_days is not null
)

select
	delay_group,
	count(*) as customer_cnt,
	count(*) filter (where first_order_review_score is not null) as reviewed_customer_cnt,
	round(avg(first_order_review_score)::numeric, 2) as avg_review_score,
	round(count(*) filter (where low_review_flag = 1)::numeric
		/ nullif(count(*) filter (where low_review_flag is not null), 0) * 100, 2) as low_review_rate
from delay_severity_base
group by delay_group
order by
	case delay_group
		when '1-3d' then 1
		when '4-7d' then 2
		when '8-13d' then 3
		when '14d plus' then 4
	end;
/*
확인 결과:
- 평균 리뷰 점수는 1~3일 지연 3.29점에서 4~7일 지연 2.09점으로 크게 낮아졌고, 저리뷰율도 32.08%에서 68.08%로 급증했다.
- 8일 이상 지연에서는 평균 리뷰 약 1.7점, 저리뷰율 약 79~80% 수준이 유지돼 4일 이상 지연을 cx 개선 기준으로 사용하는 것이 적절하다.
*/



-- =========================================================
-- 5. cx target 확인
-- =========================================================

with cx_target_summary as (
	select
		case when delivery_delay_days <= 3 then '1-3d' else '4d plus' end as delay_group,
		count(*) as customer_cnt,
		count(*) filter (where first_order_review_score is not null) as reviewed_customer_cnt,
		avg(first_order_review_score) as avg_review_score,
		count(*) filter (where low_review_flag = 1)::numeric
			/ nullif(count(*) filter (where low_review_flag is not null), 0) * 100 as low_review_rate
	from action_target_base
	where delivery_group = 'delayed' and delivery_delay_days is not null
	group by case when delivery_delay_days <= 3 then '1-3d' else '4d plus' end
)

select
	delay_group, customer_cnt,
	round(customer_cnt::numeric / sum(customer_cnt) over() * 100, 2) as delayed_customer_rate,
	reviewed_customer_cnt,
	round(avg_review_score::numeric, 2) as avg_review_score,
	round(low_review_rate, 2) as low_review_rate
from cx_target_summary
order by case delay_group when '1-3d' then 1 when '4d plus' then 2 end;

-- 4일 이상 cx target pool 규모 확인
select
	count(*) filter (where delivery_group = 'delayed' and delivery_delay_days >= 4) as target_customer_cnt,
	round(count(*) filter (where delivery_group = 'delayed' and delivery_delay_days >= 4)::numeric / count(*) * 100, 2) as target_customer_rate
from action_target_base;
/*
확인 결과:
- 4일 이상 지연 고객은 4,534명으로 전체 지연 고객의 71.35%, 전체 고객의 4.86%를 차지했다.
- 4일 이상 지연 고객의 평균 리뷰는 1.85점, 저리뷰율은 75.02%로 1~3일 지연 고객의 3.29점, 32.08%보다 크게 악화됐다.
- python 회귀에서도 payment, category, cohort를 고려한 뒤 4일 이상 지연 고객의 저리뷰 odds가 약 6.1배 높게 유지돼, 4일 이상 지연을 cx target 기준으로 사용한다.
*/


-- =========================================================
-- 6. cohort별 target 성과 차이 확인
-- =========================================================

-- q3, q4 retention target의 cohort별 재구매율
select
	cohort_quarter,
	count(*) as target_customer_cnt,
	count(*) filter (where eligible_90d = 1) as eligible_90d_customer_cnt,
	count(*) filter (where repurchase_90d = 1) as repurchase_90d_customer_cnt,
	round(count(*) filter (where repurchase_90d = 1)::numeric
		/ nullif(count(*) filter (where eligible_90d = 1), 0) * 100, 2) as repurchase_90d_rate
from action_target_base
where payment_group in ('q3', 'q4')
group by cohort_quarter
having count(*) filter (where eligible_90d = 1) >= 100
order by cohort_quarter;
/*
확인 결과 - retention:
- q3, q4 고객의 90일 재구매율은 주요 cohort별로 1.58~2.54%의 차이를 보여, 동일한 retention target 안에서도 시기별 성과 차이가 확인됐다.
- python 회귀에서도 cohort가 유의했으므로 특정 cohort를 타깃으로 선정하기보다, 이후 실험과 성과 비교에서 시기 차이를 통제하는 변수로 활용한다.
*/

-- 4일 이상 cx target의 cohort별 저리뷰율
select
	cohort_quarter,
	count(*) as target_customer_cnt,
	count(*) filter (where first_order_review_score is not null) as reviewed_customer_cnt,
	round(avg(first_order_review_score)::numeric, 2) as avg_review_score,
	round(count(*) filter (where low_review_flag = 1)::numeric
		/ nullif(count(*) filter (where low_review_flag is not null), 0) * 100, 2) as low_review_rate
from action_target_base
where delivery_group = 'delayed' and delivery_delay_days >= 4
group by cohort_quarter
having count(*) filter (where first_order_review_score is not null) >= 100
order by cohort_quarter;
/*
확인 결과 - cx:
- 4일 이상 지연 고객의 저리뷰율은 주요 cohort별로 약 65~80%의 차이를 보여, 동일한 cx target 안에서도 시기별 baseline 차이가 확인됐다.
- python 회귀에서도 cohort가 유의했으므로 특정 cohort를 cx 타깃으로 사용하지 않고, 이후 실험과 성과 비교에서 시기 차이를 통제하는 변수로 활용한다.
*/



-- =========================================================
-- 7. experiment baseline 정리
-- =========================================================

select
	'retention' as objective,
	'q3, q4' as target_rule,
	count(*) as target_customer_cnt,
	count(*) filter (where eligible_90d = 1) as analysis_customer_cnt,
	count(*) filter (where repurchase_90d = 1) as outcome_customer_cnt,
	'90d repurchase rate' as primary_kpi,
	round(count(*) filter (where repurchase_90d = 1)::numeric
		/ nullif(count(*) filter (where eligible_90d = 1), 0) * 100, 2) as baseline_rate
from action_target_base
where payment_group in ('q3', 'q4')

union all

select
	'cx' as objective,
	'4d plus delay' as target_rule,
	count(*) as target_customer_cnt,
	count(*) filter (where first_order_review_score is not null) as analysis_customer_cnt,
	count(*) filter (where low_review_flag = 1) as outcome_customer_cnt,
	'low review rate' as primary_kpi,
	round(count(*) filter (where low_review_flag = 1)::numeric
		/ nullif(count(*) filter (where low_review_flag is not null), 0) * 100, 2) as baseline_rate
from action_target_base
where delivery_group = 'delayed' and delivery_delay_days >= 4;
/*
확인 결과:
- retention은 q3, q4 고객 46,878명을 target pool로 정의했으며, 90일 관찰 가능 고객 37,691명의 baseline 재구매율은 2.12%였다.
- cx는 4일 이상 지연 고객 4,534명을 target으로 정의했으며, 리뷰 확인 가능 고객 4,404명의 baseline 저리뷰율은 75.02%였다.
- 두 baseline은 이후 a/b test의 효과 크기와 성공 기준을 설정하는 기준값으로 활용한다.
*/



-- =========================================================
-- 8. final action board
-- =========================================================

select
	'retention' as objective,
	'q3, q4 first-order customers' as target,
	count(*) as target_customer_cnt,
	'q3, q4 showed lower adjusted repurchase odds' as evidence,
	'category-based second-purchase crm experiment' as proposed_action,
	'90d repurchase rate' as primary_kpi,
	round(count(*) filter (where repurchase_90d = 1)::numeric
		/ nullif(count(*) filter (where eligible_90d = 1), 0) * 100, 2) as baseline_rate,
	'category, cohort' as context_variable
from action_target_base
where payment_group in ('q3', 'q4')

union all

select
	'cx' as objective,
	'4d plus past estimated delivery' as target,
	count(*) as target_customer_cnt,
	'4d plus delay showed 6.1x low-review odds' as evidence,
	'proactive delay communication and service recovery experiment' as proposed_action,
	'low review rate' as primary_kpi,
	round(count(*) filter (where low_review_flag = 1)::numeric
		/ nullif(count(*) filter (where low_review_flag is not null), 0) * 100, 2) as baseline_rate,
	'cohort' as context_variable
from action_target_base
where delivery_group = 'delayed' and delivery_delay_days >= 4;
/*
확인 결과:
- retention은 q3, q4 첫 구매 고객을 우선 target pool로 선정하고, category를 후속 구매 crm의 개인화 및 우선순위 context로 활용한다.
- cx는 4일 이상 배송 지연 고객을 intervention target으로 선정하고, 선제 안내와 service recovery를 통해 저리뷰 감소를 검증한다.
- retention과 cx 모두 cohort별 성과 차이가 확인돼 이후 a/b test와 성과 평가에서 시기 효과를 함께 고려한다.
- 현재 분석은 관찰데이터 기반으로 액션 대상과 baseline을 정의한 단계이며, 제안 액션의 인과적 효과는 treatment/control 기반 a/b test에서 검증한다.
*/