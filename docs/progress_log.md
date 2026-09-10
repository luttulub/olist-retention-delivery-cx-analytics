# Progress Log

## 2026-07-27 — 분석 환경 구축 및 데이터 준비

- PostgreSQL 및 DBeaver 분석 환경 구축
- Olist CSV 데이터 9개 테이블 적재 완료
- CSV 문자열 길이 및 Escape 문자 오류 해결
- 분석 편의를 위해 테이블명 정리
- 테이블별 컬럼과 의미 확인
- 데이터 딕셔너리 작성
- ERD 작성을 위한 테이블 관계 탐색 시작
- 


## 2026-07-28 — Olist 데이터 구조 파악 및 ERD 구성

### 진행 내용

- Olist 데이터셋의 테이블과 컬럼 구조를 확인했다.
- 주요 식별자의 고유성과 테이블 간 연결 관계를 검토했다.
- 원본 CSV에 실제 PK·FK 제약조건이 설정되어 있지 않아 논리적 키를 기준으로 ERD를 구성했다.

### 주요 모델링 결과

- 단일 기본키
  - `customers.customer_id`
  - `orders.order_id`
  - `products.product_id`
  - `sellers.seller_id`
  - `category.product_category_name`

- 복합 기본키
  - `order_items`: (`order_id`, `order_item_id`)
  - `order_payments`: (`order_id`, `payment_sequential`)

- 주요 관계
  - `customers` → `orders`
  - `orders` → `order_items`
  - `orders` → `order_payments`
  - `orders` → `reviews`
  - `products` → `order_items`
  - `sellers` → `order_items`
  - `category` → `products`

### 모델링 결정

- 원본 데이터 구조를 유지하기 위해 PostgreSQL에 실제 PK·FK 제약조건은 추가하지 않았다.
- DBeaver의 Virtual Key와 가상 관계를 활용해 논리적 데이터 모델을 표현했다.
- `reviews`는 신뢰할 수 있는 단일 기본키를 확인하기 어려워 PK를 지정하지 않았다.
- `geolocation_zip_code_prefix`는 중복값이 존재하므로 `geolocation` 테이블을 ERD에서 직접 연결하지 않았다.

### 산출물

- ERD: `docs/olist_Erd.png`
- 모델링 문서: `docs/data_modeling.md`

### 다음 단계

- 전체 테이블의 행 수 확인
- 주요 컬럼의 NULL 및 중복값 검증
- 주문 날짜 범위와 주문 상태값 확인
- 데이터 품질 검증 SQL 작성


## 2026-07-29~30 — Olist 데이터 품질 검증

### 진행 내용

- 데이터마트 생성 전에 원천 데이터의 품질과 조인 구조를 확인하기 위해 `sql/01_data_validation.sql` 작성을 시작했다.
- 테이블별 행 수와 논리적 기본키의 중복 여부를 확인했다.
- 데이터 적재 과정에서 `items`, `payments`, `reviews` 테이블에 중복 적재된 데이터가 있음을 확인했다.
- 해당 테이블을 다시 적재한 뒤 행 수와 논리적 키 중복 여부를 재검증했다.
- 각 검증 쿼리 아래에 확인 결과와 이후 분석에서 적용할 기준을 주석으로 기록했다.

### 중복 데이터 검증

- `orders`, `customers`, `products`, `sellers` 등 단일 기본키를 사용하는 테이블의 키 중복 여부를 확인했다.
- `items`는 `order_id`와 `order_item_id`의 조합을 기준으로 중복 여부를 확인했다.
- `payments`는 `order_id`와 `payment_sequential`의 조합을 기준으로 중복 여부를 확인했다.
- `reviews`는 신뢰할 수 있는 단일 기본키가 없어 주문별 리뷰 행 수와 전체 행의 중복 구조를 별도로 확인했다.
- 데이터 자체의 정상적인 다중 행과 적재 오류로 발생한 완전 중복을 구분해야 한다는 점을 확인했다.

### 주문당 다중 행 구조 확인

- 한 주문에 여러 상품이 포함될 수 있으므로 `items`에는 동일한 `order_id`가 여러 행 존재할 수 있다.
- 한 주문에서 여러 결제 방식이나 결제 순서가 기록될 수 있으므로 `payments`에도 동일한 `order_id`가 여러 행 존재할 수 있다.
- `reviews`를 주문별로 확인한 결과, 대부분의 주문에는 리뷰가 1개 연결되어 있지만 일부 주문에는 2개 이상의 리뷰가 연결되어 있었다.
- 리뷰 1개가 연결된 주문은 98,126건, 리뷰 2개가 연결된 주문은 543건, 리뷰 3개가 연결된 주문은 4건이었다.
- 따라서 `items`, `payments`, `reviews`를 원본 상태로 동시에 `orders`에 조인하면 주문 행이 중복되어 금액이나 주문 수가 과대 집계될 수 있다.
- 이후 주문 단위 데이터마트를 만들 때는 각 테이블을 먼저 `order_id` 기준으로 집계한 뒤 조인하기로 결정했다.

### `orders` 주요 컬럼의 null 검증

- `orders`의 주요 상태 및 날짜 컬럼에서 `null`, 빈 문자열, 공백 문자열의 개수를 확인했다.
- 현재 날짜 컬럼이 문자열 자료형이므로 `trim()`과 `nullif()`를 사용해 빈 문자열과 공백 문자열도 결측치로 처리했다.

확인 결과:

- `order_status`: null 0건
- `order_purchase_timestamp`: null 0건
- `order_approved_at`: null 160건
- `order_delivered_carrier_date`: null 1,783건
- `order_delivered_customer_date`: null 2,965건
- `order_estimated_delivery_date`: null 0건

- 주문 상태, 주문 생성일, 배송 예정일은 모든 주문에 기록되어 있었다.
- 결제 승인일과 실제 배송 관련 날짜에는 일부 null 값이 존재했다.
- 해당 null 값은 단순한 데이터 오류로 단정하지 않고, 취소·미승인·미배송 주문에서 정상적으로 발생한 값인지 `order_status`별로 추가 확인하기로 했다.

### 분석 기준 결정

- 문자열 컬럼의 결측치는 `null`뿐 아니라 빈 문자열과 공백 문자열까지 포함해 검증한다.
- 다중 행이 발생하는 테이블은 원본 상태로 동시에 조인하지 않는다.
- `items`, `payments`, `reviews`는 각각 `order_id` 단위로 먼저 집계한 뒤 `orders`와 결합한다.
- 결제 승인일과 배송 관련 날짜의 null은 주문 상태와 업무 흐름을 함께 확인한 뒤 분석 포함·제외 여부를 결정한다.
- 데이터 검증 결과와 분석 기준은 재실행 가능한 sql 쿼리와 주석으로 함께 남긴다.

### 배운 점

- 동일한 식별자가 여러 번 등장한다고 해서 모두 중복 오류인 것은 아니다.
- 주문과 상품, 결제, 리뷰처럼 일대다 관계를 가진 테이블에서는 동일한 `order_id`가 여러 행 존재하는 것이 정상일 수 있다.
- 적재 오류로 발생한 완전 중복과 데이터 구조상 정상적인 다중 행을 구분해야 한다.
- 날짜처럼 보이는 값도 문자열 자료형으로 저장되어 있으면 `null` 외에 빈 문자열과 공백 문자열을 함께 확인해야 한다.
- null 값은 발견 즉시 삭제하는 것이 아니라 주문 상태와 실제 업무 흐름을 기준으로 발생 원인을 먼저 확인해야 한다.
- 데이터마트를 만들기 전에 조인으로 행이 증가하는 구조를 검증해야 중복 집계를 방지할 수 있다.

### 현재 산출물

- 데이터 품질 검증 sql 작성 중
  - `sql/01_data_validation.sql`
- 데이터 검증 진행 내용 문서화
  - `docs/progress_log.md`

### 다음 단계

- `order_status`별 결제 승인일과 배송 관련 날짜의 null 분포 확인
- 주문 생성일 → 결제 승인일 → 택배사 전달일 → 고객 배송 완료일의 날짜 순서 검증
- 주요 테이블 간 고아 레코드 확인
- `items`, `payments`, `reviews`의 주문당 행 수 분포 추가 검증
- 취소, 미승인, 미배송 주문의 분석 포함·제외 기준 결정
- 데이터 검증 sql 정리 후 GitHub commit 및 push


## 2026-08-03 — 주문 결측치 및 날짜 순서 검증

### 진행 내용

- `orders`의 주문 상태와 핵심 날짜 컬럼에 대해 null, 빈 문자열, 공백 문자열을 검증했다.
- 주문 상태별 결측치 분포를 확인해 정상적인 구조적 결측과 데이터 품질 예외를 구분했다.
- 주문 생성, 결제 승인, 물류사 인계, 고객 배송 완료의 날짜 순서를 검증했다.
- 날짜 역전 주문의 건수, 시간 차이, 상태 분포와 실제 주문 내역을 확인했다.

### 주요 검증 결과

- 결제 승인일 null 160건, 물류사 인계일 null 1,783건, 고객 배송 완료일 null 2,965건을 확인했다.
- 대부분의 결측치는 취소, 미배송, 처리 중인 주문 상태와 일치했다.
- `delivered` 상태에서 핵심 날짜가 하나 이상 null인 주문은 23건이었다.
- 배송 완료일이 존재하는 `canceled` 주문은 6건으로, 배송 후 취소 또는 상태 불일치 가능성이 확인됐다.
- 물류사 인계일이 승인일보다 빠른 주문은 1,359건이었다.
- 물류사 인계일이 주문 생성일보다 빠른 주문은 166건이었다.
- 고객 배송 완료일이 물류사 인계일보다 빠른 주문은 23건이었다.

### 분석 반영 기준

- 원본의 결측값과 날짜를 임의로 수정하지 않는다.
- 결측치나 날짜 역전이 있는 주문을 전체 분석에서 일괄 삭제하지 않는다.
- 문제가 있는 날짜가 필요한 소요시간 분석에서만 해당 주문을 제외한다.
- 주문 수, 결제금액, 재구매 등 문제가 된 날짜를 사용하지 않는 분석에서는 주문을 유지한다.
- 물류사 인계일에 문제가 있어도 고객 배송 완료일과 배송 예정일이 유효하면 배송 지연 분석에는 포함한다.

### 다음 단계

- 고객, 주문, 상품, 판매자, 결제, 리뷰 테이블 간 고아 레코드 검증
- 주문당 `items`, `payments`, `reviews`의 다중 행 구조 최종 확인
- 데이터마트의 분석 포함·제외 기준 확정


## 2026-08-17 — 테이블 간 연결 누락 검증 완료

### 진행 내용

* 주문 분석에 사용할 주요 테이블 간 참조 관계를 검증했다.
* `orders`를 기준으로 고객, 주문상품, 결제, 리뷰 데이터가 정상적으로 연결되는지 확인했다.
* `items`의 상품 및 판매자 정보 연결 여부를 추가 검증했다.
* 상품 카테고리와 카테고리 번역 테이블 간 연결 상태를 확인했다.

### 주요 검증 결과

* `orders → customers` 연결 누락: 0건
* `items → orders` 연결 누락: 0건
* `payments → orders` 연결 누락: 0건
* `reviews → orders` 연결 누락: 0건
* `items → products` 연결 누락: 0건
* `items → sellers` 연결 누락: 0건

주문 분석에 필요한 주요 테이블 간 참조 관계는 모두 정상적으로 유지되고 있음을 확인했다.

상품 카테고리에서는 일부 예외가 확인되었다.

* 카테고리명이 비어 있는 상품: 610개
* 번역 테이블에 없는 카테고리: 2종
* 해당 상품: 총 13개

  * `portateis_cozinha_e_preparadores_de_alimentos`: 10개
  * `pc_gamer`: 3개

### 분석 반영 기준

* 주요 테이블은 참조 관계 문제 없이 데이터마트 구축에 활용한다.
* 카테고리 정보가 비어 있는 상품은 카테고리 분석에서 별도 미분류 값으로 처리한다.
* 번역 누락 카테고리는 주문 단위 마트 구축 시 별도 매핑 여부를 결정한다.
* 카테고리 정보가 필요하지 않은 주문·매출·재구매 분석에서는 해당 상품을 제외하지 않는다.

### 데이터 검증 단계 결론

`01_data_validation.sql`을 통해 중복, 결측치, 주문 날짜 순서 및 주요 테이블 간 연결 관계를 검증했다.

검증 결과를 바탕으로 원본 데이터를 일괄 삭제하거나 수정하지 않고, 각 지표에 필요한 컬럼의 유효성을 기준으로 선택적으로 데이터를 사용할 예정이다.



### 02_order_level_mart.sql 완료

* 주문 1건 = 1행을 Grain으로 하는 `order_level_mart` View 생성
* `orders + customers`를 기반으로 고객 고유 ID 연결
* `payments`, `items`, `reviews`를 `order_id` 기준으로 선집계한 뒤 JOIN하여 중복 집계 방지
* 주문별 `payment_total`, `item_count` 생성
* 배송 예정일과 실제 배송일을 이용해 `delivery_delay_days`, `delayed_flag` 생성
* 다중 리뷰 구조를 검증한 뒤 주문별 평균 `review_score` 적용
* 리뷰 작성 여부를 `reviewed_flag`로 생성
* 결제·상품·배송·리뷰 정보가 없는 주문은 삭제하지 않고 분석 목적에 맞게 null 또는 flag로 유지
* 최종 검증 결과 전체 99,441행과 distinct order_id 99,441건이 일치하여 주문 1건 = 1행 구조 확인

**다음 작업:** `03_customer_behavior_mart.sql` 생성



## 2026-08-25

### 03_customer_behavior_mart.sql 완료

* `order_level_mart`의 delivered 주문을 기준으로 고객 1명 = 1행인 `customer_behavior_mart` View 생성
* 고객별 구매 순서를 생성해 첫/두 번째/마지막 구매와 주문 횟수 집계
* `total_payment`, `average_order_value`, `first_order_payment_total` 생성
* 첫 주문 리뷰 점수와 배송 지연 여부를 첫 구매 경험 변수로 구성
* `days_to_second_order`, `purchase_span_days` 생성
* delivered 주문 종료일 `2018-08-29`를 기준으로 `eligible_30d/60d/90d` 생성
* 관찰 가능 고객만 기준으로 30/60/90일 재구매 여부 계산
* 재구매율: **30일 1.59% / 60일 1.96% / 90일 2.28%**
* 첫 구매월 기준 `cohort_month` 생성
* 최종 검증 결과 전체 고객 수와 distinct customer_unique_id가 모두 **93,358명**으로 일치

**다음 작업:** `04_order_lifecycle_analysis.sql`

### 04_order_lifecycle_analysis.sql 완료

- 전체 주문 99,441건을 기준으로 Created → Approved → Delivered 주문 Lifecycle 정의
- 결제 승인 주문 99,281건, 실제 배송 완료 주문 96,470건 확인
- 주문 상태별 분포 분석 및 미완료 주문 상태 확인
- Lifecycle 전환율 계산
  - Created → Approved: **99.84%**
  - Approved → Delivered: **97.15%**
  - Created → Delivered: **97.01%**
- 결제 승인 시점 미확인 주문 160건 분석
  - canceled 141건 / delivered 14건 / created 5건
- 승인 후 미배송 주문 2,825건 분석
  - shipped 1,107건(39.2%)으로 가장 높은 비중
- 실제 배송 완료 주문 96,470건 중 지연 주문 6,534건 확인
  - 배송 지연율 **6.77%**
  - 지연 발생 시 평균 **10.62일**
- 승인 시점 결측 14건, 배송일 결측 8건, canceled 상태의 지연 주문 1건 등 데이터 품질 예외 확인

**다음 작업:** `05_cohort_retention.sql`



## 2026-08-26

### 05_cohort_retention.sql 완료

- delivered 주문 96,478건과 고객 93,358명을 기준으로 첫 구매월 코호트 분석 수행
- 첫 구매월 기준 총 23개 코호트 구성
- 주문별 `order_month`와 `month_number`를 생성해 m+1/m+2/m+3 재구매 고객 확인
- delivered 데이터 종료일이 2018-08-29인 점을 고려해 2018-07을 마지막 완전 관찰월로 설정
  - m+1: 21개 코호트 관찰 가능
  - m+2: 20개 코호트 관찰 가능
  - m+3: 19개 코호트 관찰 가능
- 관찰기간 부족 코호트는 0%가 아닌 null로 처리
- 전체 월간 리텐션율
  - m+1: **0.48%**
  - m+2: **0.34%**
  - m+3: **0.26%**
- 전체 누적 재구매율
  - 30일: **1.59%**
  - 60일: **1.96%**
  - 90일: **2.28%**
- 코호트별 30/60/90일 재구매율 비교 및 90일 재구매율을 초기 3개월 대표 지표로 분석
- 표본이 충분한 코호트 중 2018-02의 90일 재구매율은 2.99%로 상대적으로 높았고, 2018-04와 2018-05는 각각 1.70%, 1.61%로 낮게 나타남
- 초기 소규모 코호트의 극단적 리텐션율은 표본 수를 고려해 해석에서 주의

**다음 작업:** `06_repurchase_driver_analysis.sql`

### 06_repurchase_driver_analysis.sql 완료

- 90일 관찰 가능 고객 75,387명을 기준으로 첫 주문 경험과 재구매율의 관련성 분석
- 첫 주문 배송 지연, 리뷰 점수, 첫 주문금액을 주요 driver 후보로 비교
- 배송 지연 여부별 90일 재구매율
  - 정상 배송: **2.30%**
  - 배송 지연: **2.00%**
  - 차이: **-0.30%p**
  - rate ratio: **0.87**
- 리뷰 점수를 low / middle / high / no_review로 구분해 비교
  - 90일 재구매율이 2.25~2.29% 수준으로 유사
  - low vs high 차이 **0.02%p**
- 첫 주문금액 분포 확인 후 사분위수 기준으로 Q1~Q4 구성
  - Q1: 2.46%
  - Q2: 2.41%
  - Q3: 2.16%
  - Q4: 2.07%
  - Q1 대비 Q4 **-0.39%p**
- 30/60/90일 민감도 분석 수행
  - 첫 주문금액은 모든 기간에서 저금액군의 재구매율이 상대적으로 높은 방향 유지
  - 배송 지연 고객 역시 모든 기간에서 정상 배송 고객보다 낮은 방향 유지
  - 리뷰 점수별 차이는 기간이 길어질수록 축소
- 90일 기준 효과 크기 비교
  1. 첫 주문금액 Q1 vs Q4: **0.39%p**
  2. 배송 지연 정상 vs 지연: **0.30%p**
  3. 리뷰 low vs high: **0.02%p**
- 첫 주문금액이 가장 일관된 재구매 관련 요인 후보로 나타났으며, 배송 지연이 그다음으로 확인됨
- 관측 데이터이므로 각 driver와 재구매 사이의 인과관계는 단정하지 않음

**다음 작업:** `07_business_action_targets.sql`



## 2026-08-29

### 06_repurchase_driver_analysis.sql 보강 및 최종 검증

- 기존 재구매 driver 분석의 시간 순서와 누락 변수를 재검토
- 90일 재구매 고객 1,716명 중 963명(56.12%)이 첫 주문 배송 완료 전에 이미 두 번째 주문을 한 것을 확인
- 배송 경험의 시간적 선후관계를 보정하기 위해 첫 배송 완료 이후 90일 재구매율을 추가 검증
  - 정상 배송: 1.16%
  - 배송 지연: 0.79%
  - 차이: -0.37%p
- 리뷰 점수의 역할을 재구매 driver에서 고객 경험(CX) 결과지표로 재정의
  - 정상 배송 평균 리뷰: 4.29
  - 배송 지연 평균 리뷰: 2.27
  - 정상 배송 저리뷰율: 9.28%
  - 배송 지연 저리뷰율: 62.54%
- 배송 지연 강도별 리뷰 경험 추가 분석
  - 3일 이하 지연 평균 리뷰 3.29 / 저리뷰율 32.08%
  - 4~7일 2.09 / 68.08%
  - 8~13일 1.69 / 79.79%
  - 14일 이상 1.70 / 79.00%
- 첫 주문 카테고리 구조 검증
  - 단일 카테고리 91,320명(97.82%)
  - multi_category 671명(0.72%)
  - unknown_category 1,367명(1.46%)
- 대표 카테고리를 임의 선정하지 않고 단일 카테고리는 실제 영어 카테고리명, 복수 카테고리는 multi_category로 분류
- 90일 관찰 가능 고객 1,000명 이상인 주요 실제 카테고리 19개의 재구매율 비교
  - fashion_bags_accessories 4.49%
  - bed_bath_table 3.91%
  - furniture_decor 3.40%
  - cool_stuff 0.93%
  - electronics 1.08%
- 첫 주문금액과 카테고리의 관계 추가 검증
  - Q1~Q4 각 구간 최소 100명 이상인 주요 카테고리 18개 중 13개에서 Q4 재구매율이 Q1보다 낮음
  - 일부 카테고리에서는 반대 또는 비선형 패턴 확인
- 첫 주문금액을 독립적인 영향 요인이 아닌 targeting signal로 해석하도록 최종 결론 보완
- 최종 변수 역할 정리
  - first_order_payment: targeting signal
  - delivery_delay: operational experience
  - review_score: CX metric
  - first_order_category: product context

**다음 작업:** `07_business_action_targets.sql`



## 2026-08-30

### 07_business_action_targets.sql 액션 타깃 후보 탐색

- 재구매 관련 신호와 고객 경험 변수를 결합하기 위한 `action_target_base` 구성
- 고객 규모와 90일 재구매 성과의 분모를 분리
  - 전체 타깃 규모는 해당 조건의 전체 고객 기준
  - 배송 후 90일 재구매율은 관찰 가능 고객만 분모에 포함
- 배송 완료 이후의 경험과 후속 구매 순서를 맞추기 위해 `post-delivery 90d repurchase` 지표 활용
  - 전체 고객 93,358명
  - 배송 후 90일 관찰 가능 고객 73,043명
- 첫 주문금액 × 배송 경험별 후속 90일 재구매율 비교
  - q1 + delayed: 0.46%
  - q2 + delayed: 0.55%
  - 정상 배송 고객은 q1~q4 모두 1.11~1.21% 수준
- 첫 주문금액별 배송 지연 고객 규모와 재구매 gap 비교
  - q1 delayed: 정상 배송 대비 -0.76%p
  - q2 delayed: 정상 배송 대비 -0.56%p
  - q4는 배송 지연 고객 1,800명, 지연율 7.67%로 운영상 노출 규모가 가장 큼
- 배송 지연 강도별 재구매 및 리뷰 경험 비교
  - 전체 배송 지연 고객 6,355명 중 4일 이상 지연 고객 4,534명
  - 1~3일 지연 평균 리뷰 3.29 / 저리뷰율 32.08%
  - 4~7일 2.09 / 68.08%
  - 8~13일 1.69 / 79.79%
  - 14일 이상 1.70 / 79.00%
  - 배송 후 90일 재구매율은 지연 강도에 따라 단조롭게 감소하지 않아, 4일 기준은 retention보다 CX 개선 기준으로 해석
- q1/q2 + 배송 지연 후보군의 첫 주문 카테고리 구성 확인
  - 주요 카테고리 구성은 전체 배송 지연 고객과 대체로 유사
  - telephony +3.56%p, electronics +2.00%p, garden_tools +1.22%p
  - 특정 카테고리 하나에 집중된 세그먼트는 아닌 것으로 확인
- 첫 주문금액과 배송 지연 강도를 조합한 retention 후보 세그먼트 추가 비교
  - q1/q2 + 4일 이상 지연: 고객 2,005명
  - 배송 후 90일 관찰 가능 고객 1,703명
  - 재구매 고객 9명 / 재구매율 0.53%
  - 동일 금액대 정상 배송 대비 -0.63%p
- 세분화된 세그먼트에서 낮은 재구매율이 관찰됐으나 실제 재구매 event 수가 적고, 단변량·교차 분석만으로 최종 retention 타깃을 확정하기에는 불안정하다고 판단
- 최종 타깃 선정 전 SQL에서 탐색한 재구매 후보 요인을 Python에서 통계적·다변량으로 검증한 뒤 `07_business_action_targets.sql`을 완성하기로 분석 순서 조정

### 01_repurchase_driver_validation.ipynb 시작

- 고객 단위 분석 데이터 93,358명을 Python에서 로드하고 기존 SQL mart와 고객 수가 일치하는 것을 확인
- `customer_behavior_mart`, `order_level_mart`를 기반으로 재구매 driver validation을 진행할 분석 기반 구성

**다음 작업:** 첫 주문 카테고리를 결합한 validation dataset 구성 → SQL 재구매 분석 결과 재현 → 후보 요인 통계적·다변량 검증 → `07_business_action_targets.sql` 최종 타깃 및 액션 설계



## 2026-09-02

### 01_repurchase_driver_validation.ipynb Retention 및 CX 검증

- 90일 관찰 가능 고객 75,386명, 재구매 고객 1,716명을 기준으로 Retention 로지스틱 회귀 수행
- 첫 주문금액, 첫 주문 카테고리, 첫 구매 cohort를 동시에 고려해 재구매와의 관계 검증
- 변수 단위 Wald test 결과
  - payment_group: p=0.0088
  - category_model: p<0.001
  - cohort_quarter: p<0.001
- q1을 기준으로 첫 주문금액 구간별 재구매 odds 비교
  - q2: OR 0.8851 / p=0.0752로 유의한 차이 없음
  - q3: OR 0.8156 / p=0.0041로 q1 대비 재구매 odds 약 18.4% 낮음
  - q4: OR 0.8084 / p=0.0032로 q1 대비 재구매 odds 약 19.2% 낮음
- 카테고리와 구매 시점을 함께 고려한 이후에도 q3·q4의 낮은 재구매 odds가 유지돼 첫 주문금액을 Retention targeting signal로 유지
- 배송 지연 고객을 대상으로 저리뷰 여부를 종속변수로 한 CX 로지스틱 회귀 수행
- CX 변수 단위 Wald test 결과
  - delay_group: p<0.001
  - cohort_quarter: p<0.001
  - payment_group: 유의하지 않음
  - category_model: 유의하지 않음
- 4일 이상 배송 지연 고객의 저리뷰 odds는 1~3일 지연 대비 약 6.1배 높게 나타남
  - OR 6.0907
  - 95% CI 5.3909~6.8813
  - p<0.001
- 배송 지연 기간별 저리뷰율은 1~3일 32.08%에서 4~7일 68.08%로 급증하고, 8일 이상에서는 약 79~80% 수준 유지
- 4일 이상 배송 지연을 CX 개선 대상 선정 기준으로 활용하기로 정리

**다음 작업:** `07_business_action_targets.sql`로 복귀해 Retention 타깃, CX 액션, KPI 및 최종 Action Board 설계



## 2026-09-03

### 07_business_action_targets.sql 최종 액션 타깃 설계

- Python 통계 검증 결과를 반영해 기존 payment × delivery 중심 후보 탐색 구조를 최종 액션 타깃 중심으로 재구성
- 고객 1명 = 1행의 `action_target_base`를 구성하고 retention, cx 분석에 필요한 payment, category, cohort, delivery, review 변수를 통합
  - 전체 고객 93,358명
  - 90일 관찰 가능 고객 75,387명
  - 90일 재구매 고객 1,716명
- retention target pool을 첫 주문금액 q3, q4 고객으로 선정
  - 전체 46,878명, 전체 고객의 50.21%
  - 90일 관찰 가능 고객 37,691명
  - baseline 90일 재구매율 2.12%
  - Python 회귀에서 category, cohort를 고려한 뒤에도 q3, q4의 낮은 재구매 odds가 유의하게 유지된 결과를 반영
- q3, q4 고객의 category별 90일 재구매율이 0.55~4.20%로 큰 차이를 보여 category를 단독 타깃보다 우선순위 및 CRM 개인화 context로 활용
- 배송 지연 강도별 CX를 재확인해 4일 이상 지연을 cx intervention 기준으로 선정
  - 4일 이상 지연 고객 4,534명, 전체 고객의 4.86%
  - 평균 리뷰 1.85점, 저리뷰율 75.02%
  - Python 회귀에서 payment, category, cohort를 고려한 뒤에도 1~3일 지연 대비 저리뷰 odds 약 6.1배 확인
- cohort별 성과 차이를 확인
  - q3, q4의 90일 재구매율은 주요 cohort별 1.58~2.54%
  - 4일 이상 지연 고객의 저리뷰율은 주요 cohort별 약 65~80%
  - cohort는 직접적인 타깃보다 실험 및 성과 평가에서 시기 차이를 고려하는 context 변수로 활용
- retention, cx 각각의 target 규모와 baseline KPI를 확정하고 final action board 구성
  - retention: q3, q4 → category 기반 second-purchase CRM experiment → 90d repurchase rate
  - cx: 4일 이상 지연 → proactive delay communication / service recovery experiment → low review rate
- 관찰데이터 분석 결과를 액션 대상과 baseline 정의까지 연결하고, 실제 액션 효과는 후속 A/B test에서 검증하도록 분석 범위를 구분

**다음 작업:** Olist 분석 결과를 기반으로 `ab_test_design.md` 작성 및 실험 설계

### 02_ab_test_design.ipynb A/B test 설계 및 power analysis

- `07_business_action_targets.sql`에서 정의한 retention, cx target과 baseline을 기반으로 후속 A/B test 설계
- 공통 실험 조건 설정
  - treatment / control 1:1 무작위 배정
  - 유의수준 0.05, 검정력 0.80
  - treatment / control의 표본 비율과 category, cohort 분포를 확인해 randomization 점검
- retention experiment 설계
  - target: 첫 주문금액 q3, q4 고객
  - treatment: 첫 구매 category 기반 재구매 유도 푸시
  - control: 추가 재구매 유도 메시지 없이 기존 구매 경험 유지
  - primary KPI: 90d repurchase rate
  - baseline: 2.12%
  - historical target 46,878명을 모두 90일 관찰한다고 가정할 경우 약 +0.39%p 이상의 차이를 80% 검정력으로 검출 가능
  - relative lift 기준 약 +18.3%
- cx experiment 설계
  - target: 예상 배송일 기준 4일 이상 지연 고객
  - treatment: 선제 배송 안내 + 보상 쿠폰을 포함한 service recovery
  - control: 기존 배송 지연 대응 유지
  - primary KPI: low review rate
  - secondary KPI: avg review score, review submission rate
  - baseline: 75.02%
  - 리뷰 확인 가능 historical sample 4,404명 기준 약 -3.74%p 이상의 차이를 80% 검정력으로 검출 가능
  - relative reduction 기준 약 5.0%
- 각 실험의 hypothesis, observation period, decision rule을 정의하고 통계적 유의성과 실제 비즈니스 적용 판단을 구분
- detectable effect는 현재 historical sample 규모에서 역산한 값이며 비즈니스 성공 기준인 MDE와 구분
- Olist에는 실제 treatment / control 배정 정보가 없어 실험 결과 분석은 수행하지 않고, 실제 운영에서는 MDE와 sample size를 사전 정의한 무작위 실험으로 효과를 검증하도록 한계 명시

**다음 작업:** Tableau 대시보드 구성 및 핵심 분석 결과 시각화



## 2026-09-04~10 — Tableau 대시보드 구성 및 시각화 완료

### 주요 시각화 결과

- 전체 고객 수: 93,358명
- 90일 관찰 가능 고객: 75,387명
- 90일 재구매율: 2.28%
- 4일 이상 배송 지연 고객: 4,534명

- 첫 구매 금액대별 90일 재구매율
  - Q1: 2.46%
  - Q2: 2.41%
  - Q3: 2.16%
  - Q4: 2.07%
- Q3·Q4 고객군은 전체 재구매율 2.28%보다 낮은 재구매율을 보였다.

- Q3·Q4 고객의 주요 카테고리별 재구매율은 0.55%~4.20%로 나타났다.
- 표본 안정성을 위해 90일 관찰 가능 고객이 1,000명 이상인 카테고리를 기준으로 Top 5 / Bottom 5를 비교했다.

- 배송 지연 구간별 저리뷰율
  - 1~3일: 32.08%
  - 4~7일: 68.08%
  - 8~13일: 79.79%
  - 14일 이상: 79.00%
- 지연 구간이 길어질수록 저리뷰율이 높은 수준으로 나타나는 패턴을 확인했다.

### 대시보드 구성

- KPI
  - Customers
  - 90D Eligible Customers
  - Repurchase Rate
  - Customer with 4+ Day Delay
- Retention Analysis
  - 첫 구매 금액대별 재구매율
  - Q3·Q4 고객의 카테고리별 재구매율 Top 5 / Bottom 5
- Delivery CX Analysis
  - 배송 지연 구간별 저리뷰율
- Key Insights
  - Q3·Q4 고객군의 낮은 재구매율
  - 카테고리별 재구매율 격차
  - 배송 지연 장기화와 CX 악화

### 산출물

- Tableau 분석 데이터
  - `dashboard/data/tableau_customer_source.csv`
- Tableau dashboard image
  - `dashboard/olist_customer_retention_delivery_cx_dashboard.png`
- Tableau Public dashboard
  - 최종 대시보드 게시 완료
