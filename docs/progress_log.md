# Progress Log

## 2026-07-27 — 분석 환경 구축 및 데이터 준비

- PostgreSQL 및 DBeaver 분석 환경 구축
- Olist CSV 데이터 9개 테이블 적재 완료
- CSV 문자열 길이 및 escape 문자 관련 적재 오류 해결
- 분석 편의를 위해 일부 테이블명 정리
- 테이블별 컬럼과 의미 확인
- 데이터 딕셔너리 작성
- ERD 작성을 위한 테이블 관계 탐색 시작

---

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
  - `items`: (`order_id`, `order_item_id`)
  - `payments`: (`order_id`, `payment_sequential`)

- 주요 관계
  - `customers` → `orders`
  - `orders` → `items`
  - `orders` → `payments`
  - `orders` → `reviews`
  - `products` → `items`
  - `sellers` → `items`
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

---

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
- 데이터 구조상 정상적인 다중 행과 적재 오류로 발생한 완전 중복을 구분했다.

### 주문당 다중 행 구조 확인

- 한 주문에 여러 상품이 포함될 수 있으므로 `items`에는 동일한 `order_id`가 여러 행 존재할 수 있다.
- 한 주문에서 여러 결제 방식이나 결제 순서가 기록될 수 있으므로 `payments`에도 동일한 `order_id`가 여러 행 존재할 수 있다.
- `reviews`를 주문별로 확인한 결과, 대부분의 주문에는 리뷰가 1개 연결되어 있지만 일부 주문에는 2개 이상의 리뷰가 연결되어 있었다.
- 리뷰 1개가 연결된 주문은 98,126건, 리뷰 2개는 543건, 리뷰 3개는 4건이었다.
- 따라서 `items`, `payments`, `reviews`를 원본 상태로 동시에 `orders`에 조인하면 주문 행이 증가해 금액이나 주문 수가 과대 집계될 수 있음을 확인했다.
- 이후 주문 단위 데이터마트에서는 각 테이블을 먼저 `order_id` 기준으로 집계한 뒤 조인하기로 결정했다.

### `orders` 주요 컬럼의 NULL 검증

- `orders`의 주요 상태 및 날짜 컬럼에서 NULL, 빈 문자열, 공백 문자열의 개수를 확인했다.
- 날짜 컬럼이 문자열 자료형이므로 `trim()`과 `nullif()`를 사용해 빈 문자열과 공백 문자열도 결측치로 처리했다.

확인 결과:

- `order_status`: NULL 0건
- `order_purchase_timestamp`: NULL 0건
- `order_approved_at`: NULL 160건
- `order_delivered_carrier_date`: NULL 1,783건
- `order_delivered_customer_date`: NULL 2,965건
- `order_estimated_delivery_date`: NULL 0건

- 주문 상태, 주문 생성일, 배송 예정일은 모든 주문에 기록되어 있었다.
- 결제 승인일과 실제 배송 관련 날짜에는 일부 결측값이 존재했다.
- 해당 결측값은 단순한 데이터 오류로 단정하지 않고 취소·미승인·미배송 주문에서 발생한 구조적 결측인지 `order_status`별로 추가 확인하기로 했다.

### 분석 기준 결정

- 문자열 컬럼의 결측치는 NULL뿐 아니라 빈 문자열과 공백 문자열까지 포함해 검증한다.
- 다중 행이 발생하는 테이블은 원본 상태로 동시에 조인하지 않는다.
- `items`, `payments`, `reviews`는 각각 `order_id` 단위로 먼저 집계한 뒤 `orders`와 결합한다.
- 결제 승인일과 배송 관련 날짜의 결측은 주문 상태와 업무 흐름을 함께 확인한 뒤 분석 포함·제외 여부를 결정한다.
- 데이터 검증 결과와 분석 기준은 재실행 가능한 SQL 쿼리와 주석으로 함께 남긴다.

### 다음 단계

- `order_status`별 결제 승인일과 배송 관련 날짜의 결측 분포 확인
- 주문 생성일 → 결제 승인일 → 물류사 인계일 → 고객 배송 완료일의 날짜 순서 검증
- 주요 테이블 간 고아 레코드 확인
- `items`, `payments`, `reviews`의 주문당 행 수 분포 추가 검증
- 취소, 미승인, 미배송 주문의 분석 포함·제외 기준 결정

---

## 2026-08-03 — 주문 결측치 및 날짜 순서 검증

### 진행 내용

- `orders`의 주문 상태와 핵심 날짜 컬럼에 대해 NULL, 빈 문자열, 공백 문자열을 검증했다.
- 주문 상태별 결측치 분포를 확인해 정상적인 구조적 결측과 데이터 품질 예외를 구분했다.
- 주문 생성, 결제 승인, 물류사 인계, 고객 배송 완료의 날짜 순서를 검증했다.
- 날짜 역전 주문의 건수, 시간 차이, 상태 분포와 실제 주문 내역을 확인했다.

### 주요 검증 결과

- 결제 승인일 NULL 160건, 물류사 인계일 NULL 1,783건, 고객 배송 완료일 NULL 2,965건을 확인했다.
- 대부분의 결측치는 취소, 미배송, 처리 중인 주문 상태와 일치했다.
- `delivered` 상태에서 핵심 날짜가 하나 이상 NULL인 주문은 23건이었다.
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

---

## 2026-08-17 — 데이터 검증 완료 및 주문 단위 데이터마트 구축

### 테이블 간 연결 누락 검증

- 주문 분석에 사용할 주요 테이블 간 참조 관계를 검증했다.
- `orders`를 기준으로 고객, 주문상품, 결제, 리뷰 데이터가 정상적으로 연결되는지 확인했다.
- `items`의 상품 및 판매자 정보 연결 여부를 추가 검증했다.
- 상품 카테고리와 카테고리 번역 테이블 간 연결 상태를 확인했다.

### 주요 검증 결과

- `orders → customers` 연결 누락: 0건
- `items → orders` 연결 누락: 0건
- `payments → orders` 연결 누락: 0건
- `reviews → orders` 연결 누락: 0건
- `items → products` 연결 누락: 0건
- `items → sellers` 연결 누락: 0건

주문 분석에 필요한 주요 테이블 간 참조 관계는 모두 정상적으로 유지되고 있음을 확인했다.

상품 카테고리에서는 일부 예외가 확인됐다.

- 카테고리명이 비어 있는 상품: 610개
- 번역 테이블에 없는 카테고리: 2종
- 해당 상품: 총 13개
  - `portateis_cozinha_e_preparadores_de_alimentos`: 10개
  - `pc_gamer`: 3개

### 분석 반영 기준

- 주요 테이블은 참조 관계 문제 없이 데이터마트 구축에 활용한다.
- 카테고리 정보가 비어 있는 상품은 카테고리 분석에서 별도 미분류 값으로 처리한다.
- 번역 누락 카테고리는 주문 단위 마트 구축 시 별도 처리한다.
- 카테고리 정보가 필요하지 않은 주문·결제금액·재구매 분석에서는 해당 상품을 제외하지 않는다.

### 데이터 검증 단계 결론

`01_data_validation.sql`을 통해 중복, 결측치, 주문 날짜 순서 및 주요 테이블 간 연결 관계를 검증했다.

검증 결과를 바탕으로 원본 데이터를 일괄 삭제하거나 수정하지 않고, 각 분석에 필요한 컬럼의 유효성을 기준으로 선택적으로 데이터를 사용하기로 했다.

### `02_order_level_mart.sql` 완료

- 주문 1건 = 1행을 grain으로 하는 `order_level_mart` View 생성
- `orders + customers`를 기반으로 고객 고유 ID 연결
- `payments`, `items`, `reviews`를 `order_id` 기준으로 선집계한 뒤 JOIN하여 중복 집계 방지
- 주문별 `payment_total`, `item_count` 생성
- 배송 예정일과 실제 배송일을 이용해 `delivery_delay_days`, `delayed_flag` 생성
- 다중 리뷰 구조를 검증한 뒤 주문별 평균 `review_score` 적용
- 리뷰 작성 여부를 `reviewed_flag`로 생성
- 결제·상품·배송·리뷰 정보가 없는 주문은 삭제하지 않고 분석 목적에 맞게 NULL 또는 flag로 유지
- 최종 검증 결과 전체 99,441행과 distinct `order_id` 99,441건이 일치하여 주문 1건 = 1행 구조 확인

### 다음 단계

- `03_customer_behavior_mart.sql` 생성

---

## 2026-08-25 — 고객 단위 데이터마트 및 주문 Lifecycle 분석

### `03_customer_behavior_mart.sql` 완료

- `order_level_mart`의 `delivered` 주문을 기준으로 고객 1명 = 1행인 `customer_behavior_mart` View 생성
- 고객별 구매 순서를 생성해 첫/두 번째/마지막 구매와 주문 횟수 집계
- `total_payment`, `average_order_value`, `first_order_payment_total` 생성
- 첫 주문 리뷰 점수와 배송 지연 여부를 첫 구매 경험 변수로 구성
- `days_to_second_order`, `purchase_span_days` 생성
- delivered 주문 데이터 종료일 `2018-08-29`를 기준으로 `eligible_30d`, `eligible_60d`, `eligible_90d` 생성
- 각 기간을 충분히 관찰할 수 있는 고객만 분모에 포함해 30/60/90일 재구매 여부 계산
- 누적 재구매율
  - 30일: **1.59%**
  - 60일: **1.96%**
  - 90일: **2.28%**
- 첫 구매월 기준 `cohort_month` 생성
- 최종 검증 결과 전체 고객 수와 distinct `customer_unique_id`가 모두 **93,358명**으로 일치

### `04_order_lifecycle_analysis.sql` 완료

- 전체 주문 99,441건을 기준으로 Created → Approved → Delivered 주문 Lifecycle 정의
- 결제 승인 주문 99,281건 확인
- `order_delivered_customer_date`가 존재하는 실제 배송 완료 주문 96,470건 확인
- 주문 상태별 분포와 미완료 주문 상태 확인
- Lifecycle 전환율 계산
  - Created → Approved: **99.84%**
  - Approved → Delivered: **97.15%**
  - Created → Delivered: **97.01%**
- 결제 승인 시점 미확인 주문 160건 분석
  - canceled 141건
  - delivered 14건
  - created 5건
- 승인 후 미배송 주문 2,825건 분석
  - shipped 1,107건(39.2%)으로 가장 높은 비중
- 실제 배송 완료일이 존재하는 주문 96,470건 중 지연 주문 6,534건 확인
  - 배송 지연율: **6.77%**
  - 지연 발생 시 평균 지연일: **10.62일**
- 승인 시점 결측 14건, 배송일 결측 8건, canceled 상태의 지연 주문 1건 등 데이터 품질 예외 확인

### 다음 단계

- `05_cohort_retention.sql` 작성

---

## 2026-08-26 — 코호트 리텐션 및 재구매 요인 분석

### `05_cohort_retention.sql` 완료

- `order_status = 'delivered'`인 주문 96,478건과 고객 93,358명을 기준으로 첫 구매월 코호트 분석 수행
- 첫 구매월 기준 총 23개 코호트 구성
- 주문별 `order_month`와 `month_number`를 생성해 M+1/M+2/M+3 재구매 고객 확인
- delivered 주문 데이터 종료일이 2018-08-29인 점을 고려해 2018-07을 마지막 완전 관찰월로 설정
  - M+1: 21개 코호트 관찰 가능
  - M+2: 20개 코호트 관찰 가능
  - M+3: 19개 코호트 관찰 가능
- 관찰 기간이 부족한 코호트는 0%가 아닌 NULL로 처리
- 전체 월간 리텐션율
  - M+1: **0.48%**
  - M+2: **0.34%**
  - M+3: **0.26%**
- 전체 누적 재구매율
  - 30일: **1.59%**
  - 60일: **1.96%**
  - 90일: **2.28%**
- 코호트별 30/60/90일 재구매율을 비교하고 90일 재구매율을 초기 3개월 대표 지표로 사용
- 표본이 충분한 코호트 중 2018-02의 90일 재구매율은 2.99%로 상대적으로 높았고, 2018-04와 2018-05는 각각 1.70%, 1.61%로 낮게 나타났다.
- 초기 소규모 코호트의 극단적인 리텐션율은 표본 수를 고려해 해석했다.

### `06_repurchase_driver_analysis.sql` 1차 분석 완료

- 90일 관찰 가능 고객 75,387명을 기준으로 첫 주문 경험과 재구매율의 관련성을 분석
- 첫 주문 배송 지연, 리뷰 점수, 첫 주문 결제금액을 주요 재구매 관련 후보 요인으로 비교
- 배송 지연 여부별 90일 재구매율
  - 정상 배송: **2.30%**
  - 배송 지연: **2.00%**
  - 차이: **-0.30%p**
  - rate ratio: **0.87**
- 리뷰 점수를 low / middle / high / no_review로 구분해 비교
  - 90일 재구매율은 2.25~2.29% 수준으로 유사
  - low vs high 차이: **0.02%p**
- 첫 주문 결제금액 분포를 확인한 뒤 사분위수 기준으로 Q1~Q4 구성
  - Q1: 2.46%
  - Q2: 2.41%
  - Q3: 2.16%
  - Q4: 2.07%
  - Q1 대비 Q4: **-0.39%p**
- 30/60/90일 민감도 분석 수행
  - 첫 주문 결제금액은 모든 기간에서 저금액군의 재구매율이 상대적으로 높은 방향 유지
  - 배송 지연 고객도 모든 기간에서 정상 배송 고객보다 낮은 방향 유지
  - 리뷰 점수별 차이는 기간이 길어질수록 축소
- 90일 기준 단순 효과 크기 비교
  1. 첫 주문 결제금액 Q1 vs Q4: **0.39%p**
  2. 정상 배송 vs 배송 지연: **0.30%p**
  3. 리뷰 low vs high: **0.02%p**
- 1차 탐색에서는 첫 주문 결제금액이 가장 일관된 재구매 관련 신호로 나타났으며, 배송 지연이 그다음으로 확인됐다.
- 관찰 데이터이므로 각 변수와 재구매 사이의 인과관계는 단정하지 않았다.

### 다음 단계

- `06_repurchase_driver_analysis.sql`의 시간적 선후관계 및 카테고리 변수 보강

---

## 2026-08-29 — 재구매 요인 분석 보강 및 CX 재정의

### `06_repurchase_driver_analysis.sql` 보강 및 최종 검증

- 기존 재구매 driver 분석의 시간적 선후관계와 누락 변수를 재검토했다.
- 90일 재구매 고객 1,716명 중 963명(56.12%)이 첫 주문 배송 완료 전에 이미 두 번째 주문을 한 것을 확인했다.
- 배송 경험과 후속 재구매의 시간 순서를 맞추기 위해 첫 배송 완료 이후 90일 재구매율을 추가 검증했다.
  - 정상 배송: 1.16%
  - 배송 지연: 0.79%
  - 차이: -0.37%p
- 리뷰 점수의 역할을 재구매 driver에서 고객 경험(CX) 결과지표로 재정의했다.
  - 정상 배송 평균 리뷰: 4.29
  - 배송 지연 평균 리뷰: 2.27
  - 정상 배송 저리뷰율: 9.28%
  - 배송 지연 저리뷰율: 62.54%
- 저리뷰는 리뷰 점수 1~2점으로 정의했다.
- 배송 지연 강도별 리뷰 경험 추가 분석
  - 1~3일 지연: 평균 리뷰 3.29 / 저리뷰율 32.08%
  - 4~7일 지연: 평균 리뷰 2.09 / 저리뷰율 68.08%
  - 8~13일 지연: 평균 리뷰 1.69 / 저리뷰율 79.79%
  - 14일 이상 지연: 평균 리뷰 1.70 / 저리뷰율 79.00%
- 첫 주문 카테고리 구조 검증
  - 단일 카테고리: 91,320명(97.82%)
  - `multi_category`: 671명(0.72%)
  - `unknown_category`: 1,367명(1.46%)
- 대표 카테고리를 임의로 선정하지 않고, 단일 카테고리는 실제 영문 카테고리명, 복수 카테고리는 `multi_category`로 분류했다.
- 90일 관찰 가능 고객이 1,000명 이상인 주요 실제 카테고리의 재구매율을 비교했다.
  - `fashion_bags_accessories`: 4.49%
  - `bed_bath_table`: 3.91%
  - `furniture_decor`: 3.40%
  - `cool_stuff`: 0.93%
  - `electronics`: 1.08%
- 첫 주문 결제금액과 카테고리의 관계 추가 검증
  - Q1~Q4 각 구간에 최소 100명 이상 존재하는 주요 카테고리 18개 중 13개에서 Q4 재구매율이 Q1보다 낮았다.
  - 일부 카테고리에서는 반대 또는 비선형 패턴도 확인됐다.
- 첫 주문 결제금액을 독립적인 영향 요인이 아닌 targeting signal로 해석하도록 최종 결론을 보완했다.

### 최종 변수 역할 정리

- `first_order_payment`: targeting signal
- `delivery_delay`: operational experience
- `review_score`: CX metric
- `first_order_category`: product context

### 다음 단계

- 액션 타깃 후보 탐색 후 Python을 이용한 다변량 추가 검증

---

## 2026-08-30 — 비즈니스 액션 타깃 후보 탐색 및 Python 검증 준비

### `07_business_action_targets.sql` 액션 타깃 후보 탐색

- 재구매 관련 신호와 고객 경험 변수를 결합하기 위한 `action_target_base` 구성
- 고객 규모와 재구매 성과의 분모를 분리
  - 전체 타깃 규모는 해당 조건을 충족하는 전체 고객 기준
  - 배송 완료 이후 90일 재구매율은 해당 기간을 충분히 관찰할 수 있는 고객만 분모에 포함
- 배송 경험과 후속 구매의 시간 순서를 맞추기 위해 post-delivery 90-day repurchase 지표 활용
  - 전체 고객: 93,358명
  - 배송 완료 이후 90일 관찰 가능 고객: 73,043명
- 첫 주문 결제금액 × 배송 경험별 후속 90일 재구매율 비교
  - Q1 + delayed: 0.46%
  - Q2 + delayed: 0.55%
  - 정상 배송 고객은 Q1~Q4 모두 1.11~1.21% 수준
- 첫 주문 결제금액별 배송 지연 고객 규모와 재구매 gap 비교
  - Q1 delayed: 정상 배송 대비 -0.76%p
  - Q2 delayed: 정상 배송 대비 -0.56%p
  - Q4는 배송 지연 고객 1,800명, 지연율 7.67%로 운영상 노출 규모가 가장 큼
- 배송 지연 강도별 재구매 및 리뷰 경험 비교
  - 전체 배송 지연 고객 6,355명 중 4일 이상 지연 고객 4,534명
  - 1~3일 지연 평균 리뷰 3.29 / 저리뷰율 32.08%
  - 4~7일 지연 2.09 / 68.08%
  - 8~13일 지연 1.69 / 79.79%
  - 14일 이상 지연 1.70 / 79.00%
  - 배송 완료 이후 90일 재구매율은 지연 강도에 따라 단조롭게 감소하지 않아 4일 기준은 Retention보다 CX 개선 기준으로 해석
- Q1/Q2 + 배송 지연 후보군의 첫 주문 카테고리 구성 확인
  - 주요 카테고리 구성은 전체 배송 지연 고객과 대체로 유사
  - `telephony` +3.56%p, `electronics` +2.00%p, `garden_tools` +1.22%p
  - 특정 카테고리 하나에 집중된 세그먼트는 아닌 것으로 확인
- 첫 주문 결제금액과 배송 지연 강도를 조합한 Retention 후보 세그먼트 추가 비교
  - Q1/Q2 + 4일 이상 지연: 고객 2,005명
  - 배송 후 90일 관찰 가능 고객: 1,703명
  - 재구매 고객: 9명
  - 재구매율: 0.53%
  - 동일 금액대 정상 배송 대비 -0.63%p
- 세분화된 세그먼트에서 낮은 재구매율이 관찰됐으나 실제 재구매 event 수가 적어 단변량·교차 분석만으로 최종 Retention 타깃을 확정하기에는 불안정하다고 판단했다.
- 최종 타깃 선정 전에 SQL에서 탐색한 후보 요인을 Python에서 통계적·다변량으로 검증한 뒤 `07_business_action_targets.sql`을 완성하기로 분석 순서를 조정했다.

### `01_repurchase_driver_validation.ipynb` 시작

- 고객 단위 분석 데이터 93,358명을 Python에서 로드하고 기존 SQL mart와 고객 수가 일치하는 것을 확인
- `customer_behavior_mart`, `order_level_mart`를 기반으로 검증용 분석 데이터 구성 시작

### 다음 단계

- 첫 주문 카테고리를 결합한 validation dataset 구성
- SQL 재구매 분석 결과 재현
- 후보 요인의 통계적·다변량 검증
- 검증 결과를 반영해 `07_business_action_targets.sql` 최종화

---

## 2026-09-02 — Retention 및 Delivery CX 통계 검증

### `01_repurchase_driver_validation.ipynb` 완료

#### Retention 검증

- 전체 90일 관찰 가능 고객은 75,387명이었으며, 첫 주문 결제금액 결측 1명을 제외한 **75,386명**을 Retention 로지스틱 회귀 분석에 사용했다.
- 첫 주문 결제금액, 첫 주문 카테고리, 첫 구매 cohort를 동시에 고려해 재구매와의 관계를 검증했다.
- 변수 단위 Wald test 결과
  - `payment_group`: p=0.0088
  - `category_model`: p<0.001
  - `cohort_quarter`: p<0.001
- Q1을 기준으로 첫 주문 결제금액 구간별 재구매 odds 비교
  - Q2: OR 0.8851 / p=0.0752 → 유의한 차이 없음
  - Q3: OR 0.8156 / p=0.0041 → Q1 대비 재구매 odds 약 18.4% 낮음
  - Q4: OR 0.8084 / p=0.0032 → Q1 대비 재구매 odds 약 19.2% 낮음
- 카테고리와 구매 시점을 함께 고려한 이후에도 Q3·Q4의 낮은 재구매 odds가 유지돼 첫 주문 결제금액을 Retention targeting signal로 유지했다.

#### Delivery CX 검증

- 배송 지연 고객을 대상으로 저리뷰 여부를 종속변수로 한 CX 로지스틱 회귀를 수행했다.
- 변수 단위 Wald test 결과
  - `delay_group`: p<0.001
  - `cohort_quarter`: p<0.001
  - `payment_group`: 유의하지 않음
  - `category_model`: 유의하지 않음
- 4일 이상 배송 지연 고객의 저리뷰 odds는 1~3일 지연 고객 대비 약 6.1배 높게 나타났다.
  - OR: 6.0907
  - 95% CI: 5.3909~6.8813
  - p<0.001
- 배송 지연 기간별 저리뷰율은 1~3일 32.08%에서 4~7일 68.08%로 크게 증가했고, 8일 이상에서는 약 79~80% 수준을 유지했다.
- 4일 이상 배송 지연을 CX 개선 대상 선정 기준으로 활용하기로 했다.

### 다음 단계

- 통계 검증 결과를 반영해 `07_business_action_targets.sql` 최종 타깃, KPI 및 Action Board 설계

---

## 2026-09-03 — 비즈니스 타깃 정의 및 A/B 테스트 설계

### `07_business_action_targets.sql` 최종 액션 타깃 설계

- Python 통계 검증 결과를 반영해 기존 payment × delivery 중심 후보 탐색 구조를 최종 액션 타깃 중심으로 재구성했다.
- 고객 1명 = 1행의 `action_target_base`를 구성하고 Retention/CX 분석에 필요한 payment, category, cohort, delivery, review 변수를 통합했다.
  - 전체 고객: 93,358명
  - 90일 관찰 가능 고객: 75,387명
  - 90일 재구매 고객: 1,716명
- Retention target pool을 첫 주문 결제금액 Q3·Q4 고객으로 선정했다.
  - 전체 46,878명
  - 전체 고객의 50.21%
  - 90일 관찰 가능 고객 37,691명
  - baseline 90일 재구매율 2.12%
  - Python 회귀에서 category, cohort를 함께 고려한 뒤에도 Q3·Q4의 낮은 재구매 odds가 유지된 결과를 반영
- Q3·Q4 고객의 카테고리별 90일 재구매율이 0.55~4.20%로 큰 차이를 보여 category를 단독 타깃 기준보다 우선순위 및 메시지 개인화 context로 활용하기로 했다.
- 배송 지연 강도별 CX를 재확인해 4일 이상 지연 고객을 CX intervention 대상으로 선정했다.
  - 4일 이상 지연 고객: 4,534명
  - 전체 고객의 4.86%
  - 평균 리뷰: 1.85점
  - 저리뷰율: 75.02%
  - Python 회귀에서 payment, category, cohort를 고려한 뒤에도 1~3일 지연 고객 대비 저리뷰 odds 약 6.1배 확인
- cohort별 성과 차이를 확인했다.
  - Q3·Q4의 90일 재구매율: 주요 cohort별 1.58~2.54%
  - 4일 이상 지연 고객의 저리뷰율: 주요 cohort별 약 65~80%
  - cohort는 직접적인 타깃 기준보다 실험 및 성과 평가에서 시기 차이를 고려하기 위한 context 변수로 활용
- Retention/CX 각각의 target 규모와 baseline KPI를 확정하고 최종 Action Board 구성
  - Retention: Q3·Q4 고객 → 카테고리 기반 재구매 유도 메시지 실험 → 90-day repurchase rate
  - CX: 4일 이상 지연 고객 → 선제 배송 안내 및 service recovery 실험 → low review rate
- 관찰 데이터 분석 결과는 액션 대상과 baseline 정의까지 연결하고, 실제 액션의 인과적 효과는 후속 A/B 테스트에서 검증하도록 분석 범위를 구분했다.

### `02_ab_test_design.ipynb` A/B 테스트 설계 및 검정력 분석

- `07_business_action_targets.sql`에서 정의한 Retention/CX target과 baseline을 기반으로 후속 A/B 테스트를 설계했다.
- 공통 실험 조건 설정
  - treatment / control 1:1 무작위 배정
  - 유의수준 0.05
  - 검정력 0.80
  - treatment / control의 표본 비율과 category, cohort 분포를 확인해 randomization 점검

#### Retention Experiment

- target: 첫 주문 결제금액 Q3·Q4 고객
- treatment: 첫 구매 category 기반 재구매 유도 푸시
- control: 추가 재구매 유도 메시지 없이 기존 구매 경험 유지
- primary KPI: 90-day repurchase rate
- baseline: 2.12%
- historical target 46,878명을 모두 90일 관찰한다고 가정할 경우 약 **+0.39%p** 이상의 차이를 80% 검정력으로 검출 가능
- relative lift 기준 약 **+18.3%**

#### CX Experiment

- target: 예상 배송일 기준 4일 이상 지연 고객
- treatment: 선제 배송 안내 + 보상 쿠폰을 포함한 service recovery
- control: 기존 배송 지연 대응 유지
- primary KPI: low review rate
- secondary KPI: average review score, review submission rate
- baseline: 75.02%
- 리뷰 확인 가능한 historical sample 4,404명을 기준으로 약 **-3.74%p** 이상의 차이를 80% 검정력으로 검출 가능
- relative reduction 기준 약 **5.0%**

### 실험 설계 해석 기준

- 각 실험의 hypothesis, observation period, decision rule을 정의했다.
- 통계적 유의성과 실제 비즈니스 적용 판단을 구분했다.
- 계산된 detectable effect는 현재 historical sample 규모를 기준으로 역산한 값이다.
- 실제 실험에서는 비즈니스적으로 의미 있는 효과 크기와 MDE를 사전에 정의한 뒤 필요한 sample size를 결정해야 한다.
- Olist에는 실제 treatment/control 배정 정보가 없으므로 실험 결과 분석이나 treatment effect 측정은 수행하지 않았다.
- 본 프로젝트에서는 **후속 실험 설계까지만 수행**했다.

### 다음 단계

- Tableau 대시보드 구성 및 핵심 분석 결과 시각화

---

## 2026-09-04~10 — Tableau 대시보드 구성 및 시각화 완료

### 주요 시각화 결과

- 전체 고객 수: 93,358명
- 90일 관찰 가능 고객: 75,387명
- 90일 재구매율: 2.28%
- 4일 이상 배송 지연 고객: 4,534명

#### 첫 구매 결제금액대별 90일 재구매율

- Q1: 2.46%
- Q2: 2.41%
- Q3: 2.16%
- Q4: 2.07%
- Q3·Q4 고객군의 90일 재구매율은 전체 2.28%보다 낮게 나타났다.

#### Q3·Q4 고객의 카테고리별 재구매율

- 주요 카테고리별 90일 재구매율은 0.55~4.20%로 나타났다.
- 표본 안정성을 위해 전체 90일 관찰 가능 고객이 1,000명 이상인 카테고리를 대상으로 Q3·Q4 고객의 Top 5 / Bottom 5를 비교했다.

#### 배송 지연 구간별 저리뷰율

- 1~3일: 32.08%
- 4~7일: 68.08%
- 8~13일: 79.79%
- 14일 이상: 79.00%
- 지연 기간이 긴 고객군에서 저리뷰율이 높은 수준으로 나타나는 패턴을 확인했다.

### 대시보드 구성

- KPI
  - Customers
  - 90D Eligible Customers
  - Repurchase Rate
  - Customers with 4+ Day Delay
- Retention Analysis
  - 첫 구매 결제금액대별 재구매율
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

---

## 2026-09-11 — 포트폴리오 최종 문서화 및 GitHub 정리

### README 최종 정리

- 프로젝트 제목을 `Olist Customer Retention & Delivery CX Analytics`로 정리했다.
- README 상단에서 프로젝트 목적, 핵심 지표, Dashboard, Key Insights가 빠르게 보이도록 정보 구조를 재구성했다.
- 첫 구매 결제금액 Q3·Q4가 금액 사분위 기준임을 명확하게 표현했다.
- 로지스틱 회귀는 예측 모델이 아니라 다른 관측 특성을 함께 고려한 뒤에도 연관성이 유지되는지 확인하기 위한 추가 검증으로 설명했다.
- 관찰 데이터 기반 분석이므로 변수 간 관계를 인과관계로 해석하지 않는다는 한계를 명시했다.
- A/B 테스트는 실제 실험을 수행한 것이 아니라 타깃 정의, baseline 산출, 표본 규모 및 detectable effect 계산을 포함한 **후속 실험 설계까지만 수행**했음을 명확하게 구분했다.
- Tableau Dashboard 이미지와 Public 링크를 README 상단부에 배치했다.

### Repository 정리

- Repository 이름을 `olist-retention-delivery-cx-analytics`로 변경했다.
- 프로젝트 목적에 맞지 않는 초기 계획 문서를 정리했다.
- 실제 파일이 존재하는 폴더의 불필요한 `.gitkeep` 파일을 제거했다.
- 사용하지 않는 빈 SQL placeholder 파일을 제거했다.
- `.gitignore`는 로컬 환경 및 임시 파일 제외 설정을 위해 유지했다.

### 데이터 모델 문서 동기화

- ERD의 테이블명을 현재 분석 환경과 일치하도록 수정했다.
  - `order_items` → `items`
  - `order_payments` → `payments`
- `docs/data_modeling.md`의 테이블 관계와 논리적 기본키 명칭을 실제 SQL 환경과 동기화했다.
- 원본 Olist 테이블명과 분석 환경에서 사용한 단순화된 테이블명의 차이를 문서에 명시했다.

### 최종 프로젝트 구조

- `sql/`
  - 데이터 검증
  - 주문·고객 단위 데이터마트
  - 주문 Lifecycle
  - 코호트·리텐션
  - 재구매 및 Delivery CX 분석
  - 비즈니스 액션 타깃 정의
- `notebooks/`
  - 로지스틱 회귀 기반 추가 검증
  - 후속 A/B 테스트 설계 및 검정력 분석
- `dashboard/`
  - Tableau 분석 데이터
  - 최종 Dashboard 이미지
- `docs/`
  - 데이터 모델링 및 ERD
  - 분석 진행 과정과 주요 의사결정 기록
- `README.md`
  - 프로젝트 목적, 핵심 결과, Dashboard, 분석 과정, 실험 설계 및 한계 정리

### 프로젝트 최종 상태

Olist 주문 데이터를 기반으로 **데이터 검증 → SQL 데이터마트 구축 → 리텐션 및 배송 CX 분석 → Python 통계 검증 → 비즈니스 타깃 정의 → 후속 A/B 테스트 설계 → Tableau 시각화**까지 하나의 분석 흐름으로 완성했다.

분석 결과는 관찰 데이터에서 확인한 연관성을 기반으로 하며, 제안 액션의 인과적 효과를 측정한 것은 아니다. 실제 서비스 환경에서는 treatment/control 기반의 무작위 A/B 테스트를 통해 효과를 검증해야 한다.
