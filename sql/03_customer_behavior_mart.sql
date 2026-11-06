/*
olist 고객 행동 데이터 마트 생성

목적:
- 고객 1명을 1행으로 유지하는 customer behavior mart를 생성한다.
- delivered 주문을 기준으로 고객의 구매 이력, 재구매, 구매 가치와 첫 구매 경험을 집계한다.
- 이후 재구매율, cohort retention 및 재구매 요인 분석의 기반으로 활용한다.
*/


-- =========================================================
-- 1. 고객별 구매 주문 순서 생성
-- customer_order_sequence
-- =========================================================

with delivered_orders as (
	select
		order_id,
		customer_unique_id,
		purchase_timestamp,
		order_status,
		payment_total,
		delayed_flag,
		review_score
	from order_level_mart
	where order_status = 'delivered'
	),

customer_order_sequence as (
	select
		order_id,
		customer_unique_id,
		purchase_timestamp,
		payment_total,
		delayed_flag,
		review_score,
		row_number() over (
			partition by customer_unique_id
			order by purchase_timestamp, order_id
		) as order_seq
	from delivered_orders
	)

-- 구조 확인
select
	count(*) as delivered_order_cnt,
	count(distinct order_id) as distinct_order_cnt,
	count(distinct customer_unique_id) as customer_cnt
from customer_order_sequence;
/*
확인 결과:
- delivered 주문 수와 distinct order_id가 모두 96,478건으로 일치했다.
- delivered 주문 기준 고객 수는 93,358명이며, 이후 고객별 구매 이력 집계의 기준이 된다.
*/



-- =========================================================
-- 2. 고객별 구매 이력 생성
-- customer_purchase_history
-- =========================================================


with delivered_orders as (
	select
		order_id,
		customer_unique_id,
		purchase_timestamp,
		order_status,
		payment_total,
		delayed_flag,
		review_score
	from order_level_mart
	where order_status = 'delivered'
	),

customer_order_sequence as (
	select
		order_id,
		customer_unique_id,
		purchase_timestamp,
		payment_total,
		delayed_flag,
		review_score,
		row_number() over (
			partition by customer_unique_id
			order by purchase_timestamp, order_id
			) as order_seq
	from delivered_orders
	),

customer_purchase_history as (
	select
		customer_unique_id,
		max(case when order_seq = 1 then order_id end) as first_order_id,
		max(case when order_seq = 1 then purchase_timestamp end) as first_order_timestamp,
		max(case when order_seq = 2 then purchase_timestamp end) as second_order_timestamp,
		max(purchase_timestamp) as last_order_timestamp,
		count(*) as order_count
	from customer_order_sequence
	group by customer_unique_id
	)

-- 구조 확인
select
	count(*) as customer_cnt,
	count(distinct customer_unique_id) as distinct_customer_cnt,
	count(*) filter (where second_order_timestamp is null) as one_time_customer_cnt
from customer_purchase_history;
/*
확인 결과:
- 고객 수와 distinct customer_unique_id가 모두 93,358명으로 일치해 고객 1명 = 1행이 유지됐다.
- 1회 구매 고객은 90,557명(약 97%)이며, 2회 이상 구매 고객은 2,801명(약 3%)이다.
*/



-- =========================================================
-- 3. 고객별 구매 가치 생성
-- customer_value
-- =========================================================

with delivered_orders as (
	select
		order_id,
		customer_unique_id,
		purchase_timestamp,
		order_status,
		payment_total,
		delayed_flag,
		review_score
	from order_level_mart
	where order_status = 'delivered'
	),

customer_order_sequence as (
	select
		order_id,
		customer_unique_id,
		purchase_timestamp,
		payment_total,
		delayed_flag,
		review_score,
		row_number() over (
			partition by customer_unique_id
			order by purchase_timestamp, order_id
			) as order_seq
	from delivered_orders
	),

customer_purchase_history as (
	select
		customer_unique_id,
		max(case when order_seq = 1 then order_id end) as first_order_id,
		max(case when order_seq = 1 then purchase_timestamp end) as first_order_timestamp,
		max(case when order_seq = 2 then purchase_timestamp end) as second_order_timestamp,
		max(purchase_timestamp) as last_order_timestamp,
		count(*) as order_count
	from customer_order_sequence
	group by customer_unique_id
	),

customer_value as (
	select
		customer_unique_id,
		sum(payment_total) as total_payment,
		avg(payment_total) as average_order_value,
		max(case when order_seq = 1 then payment_total end) as first_order_payment_total
	from customer_order_sequence
	group by customer_unique_id
	)

-- 구조 확인
select
	count(*) as customer_cnt,
	count(distinct customer_unique_id) as distinct_customer_cnt,
	count(*) filter (where total_payment is null) as null_total_payment_cnt,
	count(*) filter (where first_order_payment_total is null) as null_first_payment_cnt
from customer_value;
/*
확인 결과:
- 고객 수와 distinct customer_unique_id가 모두 93,358명으로 일치했다.
- 결제 정보가 누락된 고객 1명은 total_payment와 first_order_payment_total이 null이다.
*/



-- =========================================================
-- 4. 첫 구매 경험 정보 생성
-- first_order_experience
-- =========================================================

with delivered_orders as (
	select
		order_id,
		customer_unique_id,
		purchase_timestamp,
		order_status,
		payment_total,
		delayed_flag,
		review_score
	from order_level_mart
	where order_status = 'delivered'
	),

customer_order_sequence as (
	select
		order_id,
		customer_unique_id,
		purchase_timestamp,
		payment_total,
		delayed_flag,
		review_score,
		row_number() over (
			partition by customer_unique_id
			order by purchase_timestamp, order_id
			) as order_seq
	from delivered_orders
	),

customer_purchase_history as (
	select
		customer_unique_id,
		max(case when order_seq = 1 then order_id end) as first_order_id,
		max(case when order_seq = 1 then purchase_timestamp end) as first_order_timestamp,
		max(case when order_seq = 2 then purchase_timestamp end) as second_order_timestamp,
		max(purchase_timestamp) as last_order_timestamp,
		count(*) as order_count
	from customer_order_sequence
	group by customer_unique_id
	),

customer_value as (
	select
		customer_unique_id,
		sum(payment_total) as total_payment,
		avg(payment_total) as average_order_value,
		max(case when order_seq = 1 then payment_total end) as first_order_payment_total
	from customer_order_sequence
	group by customer_unique_id
	),
	
first_order_experience as (
	select
		customer_unique_id,
		review_score as first_order_review_score,
		delayed_flag as first_order_delayed_flag
	from customer_order_sequence
	where order_seq = 1
	)

-- 구조 확인
select
	count(*) as customer_cnt,
	count(distinct customer_unique_id) as distinct_customer_cnt,
	count(*) filter (where first_order_review_score is null) as null_review_score_cnt,
	count(*) filter (where first_order_delayed_flag is null) as null_delayed_flag_cnt
from first_order_experience;
/*
확인 결과:
- 고객 수와 distinct customer_unique_id가 모두 93,358명으로 일치했다.
- 첫 주문 리뷰 점수 null은 615건, 첫 주문 배송 지연 여부 null은 8건이다.
*/



-- =========================================================
-- 5. 구매 기간 변수 생성
-- customer_purchase_period
-- =========================================================

with delivered_orders as (
	select
		order_id,
		customer_unique_id,
		purchase_timestamp,
		order_status,
		payment_total,
		delayed_flag,
		review_score
	from order_level_mart
	where order_status = 'delivered'
	),

customer_order_sequence as (
	select
		order_id,
		customer_unique_id,
		purchase_timestamp,
		payment_total,
		delayed_flag,
		review_score,
		row_number() over (
			partition by customer_unique_id
			order by purchase_timestamp, order_id
			) as order_seq
	from delivered_orders
	),

customer_purchase_history as (
	select
		customer_unique_id,
		max(case when order_seq = 1 then order_id end) as first_order_id,
		max(case when order_seq = 1 then purchase_timestamp end) as first_order_timestamp,
		max(case when order_seq = 2 then purchase_timestamp end) as second_order_timestamp,
		max(purchase_timestamp) as last_order_timestamp,
		count(*) as order_count
	from customer_order_sequence
	group by customer_unique_id
	),

customer_value as (
	select
		customer_unique_id,
		sum(payment_total) as total_payment,
		avg(payment_total) as average_order_value,
		max(case when order_seq = 1 then payment_total end) as first_order_payment_total
	from customer_order_sequence
	group by customer_unique_id
	),
	
first_order_experience as (
	select
		customer_unique_id,
		review_score as first_order_review_score,
		delayed_flag as first_order_delayed_flag
	from customer_order_sequence
	where order_seq = 1
	),
	
customer_purchase_period as (
	select
		customer_unique_id,
		case
			when second_order_timestamp is null then null
			else nullif(trim(second_order_timestamp), '')::date
				- nullif(trim(first_order_timestamp), '')::date
		end as days_to_second_order,
		nullif(trim(last_order_timestamp), '')::date
			- nullif(trim(first_order_timestamp), '')::date as purchase_span_days
	from customer_purchase_history
	)

-- 구조 확인
select
	count(*) as customer_cnt,
	count(distinct customer_unique_id) as distinct_customer_cnt,
	count(*) filter (where days_to_second_order is null) as null_second_order_days_cnt,
	count(*) filter (where purchase_span_days = 0) as zero_purchase_span_cnt
from customer_purchase_period;
/*
확인 결과:
- 고객 수와 distinct customer_unique_id가 모두 93,358명으로 일치했다.
- days_to_second_order null 90,557건은 1회 구매 고객 수와 일치하며, purchase_span_days 0일은 91,343건이다.
*/



-- =========================================================
-- 6. 관찰 가능 여부 생성
-- customer_eligibility
-- =========================================================

-- 관찰 종료일 확인
select
	max(nullif(trim(purchase_timestamp), '')::timestamp)::date as all_order_end_date,
	max(case
		when order_status = 'delivered' then nullif(trim(purchase_timestamp), '')::timestamp
		end)::date as delivered_order_end_date
from order_level_mart;
/*
확인 결과:
- 전체 주문은 2018-10-17까지 존재하지만 delivered 주문은 2018-08-29까지 확인됐다.
- 재구매를 delivered 주문 기준으로 정의했으므로 관찰 종료일은 2018-08-29로 설정한다.
*/

with delivered_orders as (
	select
		order_id,
		customer_unique_id,
		purchase_timestamp,
		order_status,
		payment_total,
		delayed_flag,
		review_score
	from order_level_mart
	where order_status = 'delivered'
	),

customer_order_sequence as (
	select
		order_id,
		customer_unique_id,
		purchase_timestamp,
		payment_total,
		delayed_flag,
		review_score,
		row_number() over (
			partition by customer_unique_id
			order by purchase_timestamp, order_id
			) as order_seq
	from delivered_orders
	),

customer_purchase_history as (
	select
		customer_unique_id,
		max(case when order_seq = 1 then order_id end) as first_order_id,
		max(case when order_seq = 1 then purchase_timestamp end) as first_order_timestamp,
		max(case when order_seq = 2 then purchase_timestamp end) as second_order_timestamp,
		max(purchase_timestamp) as last_order_timestamp,
		count(*) as order_count
	from customer_order_sequence
	group by customer_unique_id
	),

customer_value as (
	select
		customer_unique_id,
		sum(payment_total) as total_payment,
		avg(payment_total) as average_order_value,
		max(case when order_seq = 1 then payment_total end) as first_order_payment_total
	from customer_order_sequence
	group by customer_unique_id
	),
	
first_order_experience as (
	select
		customer_unique_id,
		review_score as first_order_review_score,
		delayed_flag as first_order_delayed_flag
	from customer_order_sequence
	where order_seq = 1
	),
	
customer_purchase_period as (
	select
		customer_unique_id,
		case
			when second_order_timestamp is null then null
			else nullif(trim(second_order_timestamp), '')::date
				- nullif(trim(first_order_timestamp), '')::date
		end as days_to_second_order,
		nullif(trim(last_order_timestamp), '')::date
			- nullif(trim(first_order_timestamp), '')::date as purchase_span_days
	from customer_purchase_history
	),
	
customer_eligibility as (
	select
		customer_unique_id,
		case
			when nullif(trim(first_order_timestamp), '')::date <= date '2018-08-29' - 30 then 1
			else 0
		end as eligible_30d,
		case
			when nullif(trim(first_order_timestamp), '')::date <= date '2018-08-29' - 60 then 1
			else 0
		end as eligible_60d,
		case
			when nullif(trim(first_order_timestamp), '')::date <= date '2018-08-29' - 90 then 1
			else 0
		end as eligible_90d
	from customer_purchase_history
	)

-- 구조 확인
select
	count(*) as customer_cnt,
	count(distinct customer_unique_id) as distinct_customer_cnt,
	count(*) filter (where eligible_30d = 1) as eligible_30d_cnt,
	count(*) filter (where eligible_60d = 1) as eligible_60d_cnt,
	count(*) filter (where eligible_90d = 1) as eligible_90d_cnt
from customer_eligibility;
/*
확인 결과:
- 고객 수와 distinct customer_unique_id가 모두 93,358명으로 일치했다.
- 관찰 가능 고객은 30일 86,909명(93.1%), 60일 81,265명(87.0%), 90일 75,387명(80.8%)이다.
*/



-- =========================================================
-- 7. 기간별 재구매 여부 생성
-- customer_repurchase
-- =========================================================

with delivered_orders as (
	select
		order_id,
		customer_unique_id,
		purchase_timestamp,
		order_status,
		payment_total,
		delayed_flag,
		review_score
	from order_level_mart
	where order_status = 'delivered'
	),

customer_order_sequence as (
	select
		order_id,
		customer_unique_id,
		purchase_timestamp,
		payment_total,
		delayed_flag,
		review_score,
		row_number() over (
			partition by customer_unique_id
			order by purchase_timestamp, order_id
			) as order_seq
	from delivered_orders
	),

customer_purchase_history as (
	select
		customer_unique_id,
		max(case when order_seq = 1 then order_id end) as first_order_id,
		max(case when order_seq = 1 then purchase_timestamp end) as first_order_timestamp,
		max(case when order_seq = 2 then purchase_timestamp end) as second_order_timestamp,
		max(purchase_timestamp) as last_order_timestamp,
		count(*) as order_count
	from customer_order_sequence
	group by customer_unique_id
	),

customer_value as (
	select
		customer_unique_id,
		sum(payment_total) as total_payment,
		avg(payment_total) as average_order_value,
		max(case when order_seq = 1 then payment_total end) as first_order_payment_total
	from customer_order_sequence
	group by customer_unique_id
	),
	
first_order_experience as (
	select
		customer_unique_id,
		review_score as first_order_review_score,
		delayed_flag as first_order_delayed_flag
	from customer_order_sequence
	where order_seq = 1
	),
	
customer_purchase_period as (
	select
		customer_unique_id,
		case
			when second_order_timestamp is null then null
			else nullif(trim(second_order_timestamp), '')::date
				- nullif(trim(first_order_timestamp), '')::date
		end as days_to_second_order,
		nullif(trim(last_order_timestamp), '')::date
			- nullif(trim(first_order_timestamp), '')::date as purchase_span_days
	from customer_purchase_history
	),
	
customer_eligibility as (
	select
		customer_unique_id,
		case
			when nullif(trim(first_order_timestamp), '')::date <= date '2018-08-29' - 30 then 1
			else 0
		end as eligible_30d,
		case
			when nullif(trim(first_order_timestamp), '')::date <= date '2018-08-29' - 60 then 1
			else 0
		end as eligible_60d,
		case
			when nullif(trim(first_order_timestamp), '')::date <= date '2018-08-29' - 90 then 1
			else 0
		end as eligible_90d
	from customer_purchase_history
	),
	
customer_repurchase as (
	select
		p.customer_unique_id,
		case
			when e.eligible_30d = 0 then null
			when p.days_to_second_order <= 30 then 1
			else 0
		end as repurchase_30d,
		case
			when e.eligible_60d = 0 then null
			when p.days_to_second_order <= 60 then 1
			else 0
		end as repurchase_60d,
		case
			when e.eligible_90d = 0 then null
			when p.days_to_second_order <= 90 then 1
			else 0
		end as repurchase_90d
	from customer_purchase_period p
		left join customer_eligibility e
			on p.customer_unique_id = e.customer_unique_id
	)
	
-- 구조 확인
select
	count(*) as customer_cnt,
	count(distinct customer_unique_id) as distinct_customer_cnt,
	count(*) filter (where repurchase_30d = 1) as repurchase_30d_cnt,
	count(*) filter (where repurchase_60d = 1) as repurchase_60d_cnt,
	count(*) filter (where repurchase_90d = 1) as repurchase_90d_cnt
from customer_repurchase;
/*
확인 결과:
- 고객 수와 distinct customer_unique_id가 모두 93,358명으로 일치했다.
- 관찰 가능 고객 기준 재구매 고객은 30일 1,381명(1.59%), 60일 1,590명(1.96%), 90일 1,716명(2.28%)이다.
*/



-- =========================================================
-- 8. 코호트 정보 생성
-- customer_cohort
-- =========================================================

with delivered_orders as (
	select
		order_id,
		customer_unique_id,
		purchase_timestamp,
		order_status,
		payment_total,
		delayed_flag,
		review_score
	from order_level_mart
	where order_status = 'delivered'
	),

customer_order_sequence as (
	select
		order_id,
		customer_unique_id,
		purchase_timestamp,
		payment_total,
		delayed_flag,
		review_score,
		row_number() over (
			partition by customer_unique_id
			order by purchase_timestamp, order_id
			) as order_seq
	from delivered_orders
	),

customer_purchase_history as (
	select
		customer_unique_id,
		max(case when order_seq = 1 then order_id end) as first_order_id,
		max(case when order_seq = 1 then purchase_timestamp end) as first_order_timestamp,
		max(case when order_seq = 2 then purchase_timestamp end) as second_order_timestamp,
		max(purchase_timestamp) as last_order_timestamp,
		count(*) as order_count
	from customer_order_sequence
	group by customer_unique_id
	),

customer_value as (
	select
		customer_unique_id,
		sum(payment_total) as total_payment,
		avg(payment_total) as average_order_value,
		max(case when order_seq = 1 then payment_total end) as first_order_payment_total
	from customer_order_sequence
	group by customer_unique_id
	),
	
first_order_experience as (
	select
		customer_unique_id,
		review_score as first_order_review_score,
		delayed_flag as first_order_delayed_flag
	from customer_order_sequence
	where order_seq = 1
	),
	
customer_purchase_period as (
	select
		customer_unique_id,
		case
			when second_order_timestamp is null then null
			else nullif(trim(second_order_timestamp), '')::date
				- nullif(trim(first_order_timestamp), '')::date
		end as days_to_second_order,
		nullif(trim(last_order_timestamp), '')::date
			- nullif(trim(first_order_timestamp), '')::date as purchase_span_days
	from customer_purchase_history
	),
	
customer_eligibility as (
	select
		customer_unique_id,
		case
			when nullif(trim(first_order_timestamp), '')::date <= date '2018-08-29' - 30 then 1
			else 0
		end as eligible_30d,
		case
			when nullif(trim(first_order_timestamp), '')::date <= date '2018-08-29' - 60 then 1
			else 0
		end as eligible_60d,
		case
			when nullif(trim(first_order_timestamp), '')::date <= date '2018-08-29' - 90 then 1
			else 0
		end as eligible_90d
	from customer_purchase_history
	),
	
customer_repurchase as (
	select
		p.customer_unique_id,
		case
			when e.eligible_30d = 0 then null
			when p.days_to_second_order <= 30 then 1
			else 0
		end as repurchase_30d,
		case
			when e.eligible_60d = 0 then null
			when p.days_to_second_order <= 60 then 1
			else 0
		end as repurchase_60d,
		case
			when e.eligible_90d = 0 then null
			when p.days_to_second_order <= 90 then 1
			else 0
		end as repurchase_90d
	from customer_purchase_period p
		left join customer_eligibility e
			on p.customer_unique_id = e.customer_unique_id
	),
	
customer_cohort as (
	select
		customer_unique_id,
		date_trunc('month',nullif(trim(first_order_timestamp), '')::timestamp)::date as cohort_month
	from customer_purchase_history
	)

-- 구조 확인
select
	count(*) as customer_cnt,
	count(distinct customer_unique_id) as distinct_customer_cnt,
	count(*) filter (where cohort_month is null) as null_cohort_cnt,
	min(cohort_month) as first_cohort_month,
	max(cohort_month) as last_cohort_month
from customer_cohort;
/*
확인 결과:
- 고객 수와 distinct customer_unique_id가 모두 93,358명으로 일치했고 cohort_month null은 없었다.
- 첫 구매 코호트는 2016-09부터 2018-08까지 분포한다.
*/



-- =========================================================
-- 9. 고객 정보 전체 결합
-- customer_behavior_base
-- =========================================================
with delivered_orders as (
	select
		order_id,
		customer_unique_id,
		purchase_timestamp,
		order_status,
		payment_total,
		delayed_flag,
		review_score
	from order_level_mart
	where order_status = 'delivered'
	),

customer_order_sequence as (
	select
		order_id,
		customer_unique_id,
		purchase_timestamp,
		payment_total,
		delayed_flag,
		review_score,
		row_number() over (
			partition by customer_unique_id
			order by purchase_timestamp, order_id
			) as order_seq
	from delivered_orders
	),

customer_purchase_history as (
	select
		customer_unique_id,
		max(case when order_seq = 1 then order_id end) as first_order_id,
		max(case when order_seq = 1 then purchase_timestamp end) as first_order_timestamp,
		max(case when order_seq = 2 then purchase_timestamp end) as second_order_timestamp,
		max(purchase_timestamp) as last_order_timestamp,
		count(*) as order_count
	from customer_order_sequence
	group by customer_unique_id
	),

customer_value as (
	select
		customer_unique_id,
		sum(payment_total) as total_payment,
		avg(payment_total) as average_order_value,
		max(case when order_seq = 1 then payment_total end) as first_order_payment_total
	from customer_order_sequence
	group by customer_unique_id
	),
	
first_order_experience as (
	select
		customer_unique_id,
		review_score as first_order_review_score,
		delayed_flag as first_order_delayed_flag
	from customer_order_sequence
	where order_seq = 1
	),
	
customer_purchase_period as (
	select
		customer_unique_id,
		case
			when second_order_timestamp is null then null
			else nullif(trim(second_order_timestamp), '')::date
				- nullif(trim(first_order_timestamp), '')::date
		end as days_to_second_order,
		nullif(trim(last_order_timestamp), '')::date
			- nullif(trim(first_order_timestamp), '')::date as purchase_span_days
	from customer_purchase_history
	),
	
customer_eligibility as (
	select
		customer_unique_id,
		case
			when nullif(trim(first_order_timestamp), '')::date <= date '2018-08-29' - 30 then 1
			else 0
		end as eligible_30d,
		case
			when nullif(trim(first_order_timestamp), '')::date <= date '2018-08-29' - 60 then 1
			else 0
		end as eligible_60d,
		case
			when nullif(trim(first_order_timestamp), '')::date <= date '2018-08-29' - 90 then 1
			else 0
		end as eligible_90d
	from customer_purchase_history
	),
	
customer_repurchase as (
	select
		p.customer_unique_id,
		case
			when e.eligible_30d = 0 then null
			when p.days_to_second_order <= 30 then 1
			else 0
		end as repurchase_30d,
		case
			when e.eligible_60d = 0 then null
			when p.days_to_second_order <= 60 then 1
			else 0
		end as repurchase_60d,
		case
			when e.eligible_90d = 0 then null
			when p.days_to_second_order <= 90 then 1
			else 0
		end as repurchase_90d
	from customer_purchase_period p
		left join customer_eligibility e
			on p.customer_unique_id = e.customer_unique_id
	),
	
customer_cohort as (
	select
		customer_unique_id,
		date_trunc(
			'month',
			nullif(trim(first_order_timestamp), '')::timestamp
			)::date as cohort_month
	from customer_purchase_history
	),
	
customer_behavior_base as (
	select
		h.customer_unique_id,
		h.first_order_id,
		h.first_order_timestamp,
		h.second_order_timestamp,
		h.last_order_timestamp,
		h.order_count,
		v.total_payment,
		v.average_order_value,
		v.first_order_payment_total,
		p.days_to_second_order,
		p.purchase_span_days,
		e.eligible_30d,
		e.eligible_60d,
		e.eligible_90d,
		r.repurchase_30d,
		r.repurchase_60d,
		r.repurchase_90d,
		f.first_order_review_score,
		f.first_order_delayed_flag,
		c.cohort_month
	from customer_purchase_history h
		left join customer_value v
			on h.customer_unique_id = v.customer_unique_id
		left join customer_purchase_period p
			on h.customer_unique_id = p.customer_unique_id
		left join customer_eligibility e
			on h.customer_unique_id = e.customer_unique_id
		left join customer_repurchase r
			on h.customer_unique_id = r.customer_unique_id
		left join first_order_experience f
			on h.customer_unique_id = f.customer_unique_id
		left join customer_cohort c
			on h.customer_unique_id = c.customer_unique_id
	)

-- 구조 확인
select
	count(*) as customer_cnt,
	count(distinct customer_unique_id) as distinct_customer_cnt
from customer_behavior_base;
/*
확인 결과:
- 고객 수와 distinct customer_unique_id가 모두 93,358명으로 일치했다.
- 고객 단위 CTE 결합 후에도 고객 1명 = 1행 구조가 유지됐다.
*/



-- =========================================================
-- 10. customer behavior mart 생성
-- =========================================================

drop view if exists customer_behavior_mart;

create view customer_behavior_mart as

with delivered_orders as (
	select
		order_id,
		customer_unique_id,
		purchase_timestamp,
		order_status,
		payment_total,
		delayed_flag,
		review_score
	from order_level_mart
	where order_status = 'delivered'
	),

customer_order_sequence as (
	select
		order_id,
		customer_unique_id,
		purchase_timestamp,
		payment_total,
		delayed_flag,
		review_score,
		row_number() over (
			partition by customer_unique_id
			order by purchase_timestamp, order_id
			) as order_seq
	from delivered_orders
	),

customer_purchase_history as (
	select
		customer_unique_id,
		max(case when order_seq = 1 then order_id end) as first_order_id,
		max(case when order_seq = 1 then purchase_timestamp end) as first_order_timestamp,
		max(case when order_seq = 2 then purchase_timestamp end) as second_order_timestamp,
		max(purchase_timestamp) as last_order_timestamp,
		count(*) as order_count
	from customer_order_sequence
	group by customer_unique_id
	),

customer_value as (
	select
		customer_unique_id,
		sum(payment_total) as total_payment,
		avg(payment_total) as average_order_value,
		max(case when order_seq = 1 then payment_total end) as first_order_payment_total
	from customer_order_sequence
	group by customer_unique_id
	),

first_order_experience as (
	select
		customer_unique_id,
		review_score as first_order_review_score,
		delayed_flag as first_order_delayed_flag
	from customer_order_sequence
	where order_seq = 1
	),

customer_purchase_period as (
	select
		customer_unique_id,
		case
			when second_order_timestamp is null then null
			else nullif(trim(second_order_timestamp), '')::date
				- nullif(trim(first_order_timestamp), '')::date
		end as days_to_second_order,
		nullif(trim(last_order_timestamp), '')::date
			- nullif(trim(first_order_timestamp), '')::date as purchase_span_days
	from customer_purchase_history
	),

customer_eligibility as (
	select
		customer_unique_id,
		case
			when nullif(trim(first_order_timestamp), '')::date <= date '2018-08-29' - 30 then 1
			else 0
		end as eligible_30d,
		case
			when nullif(trim(first_order_timestamp), '')::date <= date '2018-08-29' - 60 then 1
			else 0
		end as eligible_60d,
		case
			when nullif(trim(first_order_timestamp), '')::date <= date '2018-08-29' - 90 then 1
			else 0
		end as eligible_90d
	from customer_purchase_history
	),

customer_repurchase as (
	select
		p.customer_unique_id,
		case
			when e.eligible_30d = 0 then null
			when p.days_to_second_order <= 30 then 1
			else 0
		end as repurchase_30d,
		case
			when e.eligible_60d = 0 then null
			when p.days_to_second_order <= 60 then 1
			else 0
		end as repurchase_60d,
		case
			when e.eligible_90d = 0 then null
			when p.days_to_second_order <= 90 then 1
			else 0
		end as repurchase_90d
	from customer_purchase_period p
		left join customer_eligibility e
			on p.customer_unique_id = e.customer_unique_id
	),

customer_cohort as (
	select
		customer_unique_id,
		date_trunc(
			'month',
			nullif(trim(first_order_timestamp), '')::timestamp
			)::date as cohort_month
	from customer_purchase_history
	),

customer_behavior_base as (
	select
		h.customer_unique_id,
		h.first_order_id,
		h.first_order_timestamp,
		h.second_order_timestamp,
		h.last_order_timestamp,
		h.order_count,
		v.total_payment,
		v.average_order_value,
		v.first_order_payment_total,
		p.days_to_second_order,
		p.purchase_span_days,
		e.eligible_30d,
		e.eligible_60d,
		e.eligible_90d,
		r.repurchase_30d,
		r.repurchase_60d,
		r.repurchase_90d,
		f.first_order_review_score,
		f.first_order_delayed_flag,
		c.cohort_month
	from customer_purchase_history h
		left join customer_value v
			on h.customer_unique_id = v.customer_unique_id
		left join customer_purchase_period p
			on h.customer_unique_id = p.customer_unique_id
		left join customer_eligibility e
			on h.customer_unique_id = e.customer_unique_id
		left join customer_repurchase r
			on h.customer_unique_id = r.customer_unique_id
		left join first_order_experience f
			on h.customer_unique_id = f.customer_unique_id
		left join customer_cohort c
			on h.customer_unique_id = c.customer_unique_id
	)

select *
from customer_behavior_base;

select *
from customer_behavior_mart;

-- 최종 mart 구조 확인
select
	count(*) as customer_cnt,
	count(distinct customer_unique_id) as distinct_customer_cnt,
	count(*) filter (where total_payment is null) as null_total_payment_cnt,
	count(*) filter (where first_order_review_score is null) as null_review_score_cnt,
	count(*) filter (where first_order_delayed_flag is null) as null_delayed_flag_cnt,
	count(*) filter (where repurchase_30d = 1) as repurchase_30d_cnt,
	count(*) filter (where repurchase_60d = 1) as repurchase_60d_cnt,
	count(*) filter (where repurchase_90d = 1) as repurchase_90d_cnt
from customer_behavior_mart;
/*
확인 결과:
- 전체 고객 수와 distinct customer_unique_id가 모두 93,358명으로 일치해 고객 1명 = 1행 구조가 유지됐다.
- 주요 null 및 30/60/90일 재구매 고객 수도 이전 단계 검증 결과와 모두 일치했다.
*/