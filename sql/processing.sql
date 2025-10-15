/* ============================================================
프로젝트명: 이커머스 퍼널(Funnel) + A/B 테스트 분석
데이터 출처: Kaggle - E-commerce Events History in Electronics Store
작성자: 한솔 
목적:
  - 사용자 행동 로그 기반 퍼널(Funnel) 전환 구조 분석
  - 세션 단위 행동 데이터를 A/B 테스트용으로 가공
  - 전환율(view→cart→purchase) 단계별 비율 계산
============================================================ */


/* ------------------------------------------------------------
[1단계] CSV → DuckDB 테이블 생성
설명:
 - 원본 CSV 데이터를 DuckDB로 불러와 분석용 테이블 생성
 - 한 행 = 한 사용자의 행동 로그 (view, cart, purchase 등)
------------------------------------------------------------ */
CREATE TABLE events AS
SELECT *
FROM read_csv_auto('/Users/hansol/Documents/data_projects/1.ecommerce_funnel_abtest/data/events.csv');


/* ------------------------------------------------------------
[2단계] 데이터 구조 및 기본 분포 확인
------------------------------------------------------------ */
-- 샘플 5
SELECT * 
FROM events
LIMIT 5;

-- 총 행 개수
SELECT COUNT(*) AS total_rows
FROM events;

-- 이벤트 타입별 분포
SELECT event_type, COUNT(*) AS event_count
FROM events
GROUP BY event_type
ORDER BY event_count DESC;


/* ------------------------------------------------------------
[2-1단계] 전체 컬럼별 결측치 현황
------------------------------------------------------------ */
SELECT 
    COUNT(*) AS total_rows,
    SUM(CASE WHEN event_time IS NULL THEN 1 ELSE 0 END) AS null_event_time,
    SUM(CASE WHEN event_type IS NULL THEN 1 ELSE 0 END) AS null_event_type,
    SUM(CASE WHEN product_id IS NULL THEN 1 ELSE 0 END) AS null_product_id,
    SUM(CASE WHEN category_id IS NULL THEN 1 ELSE 0 END) AS null_category_id,
    SUM(CASE WHEN category_code IS NULL THEN 1 ELSE 0 END) AS null_category_code,
    SUM(CASE WHEN brand IS NULL THEN 1 ELSE 0 END) AS null_brand,
    SUM(CASE WHEN price IS NULL THEN 1 ELSE 0 END) AS null_price,
    SUM(CASE WHEN user_id IS NULL THEN 1 ELSE 0 END) AS null_user_id,
    SUM(CASE WHEN user_session IS NULL THEN 1 ELSE 0 END) AS null_user_session
FROM events;


/* ------------------------------------------------------------
[3단계] 주요 컬럼 결측치 확인
설명:
 - 퍼널 분석에 중요한 3개 컬럼(category_code, brand, user_session) 집중 점검
------------------------------------------------------------ */
SELECT
    SUM(CASE WHEN category_code IS NULL THEN 1 ELSE 0 END) AS null_category_code,
    SUM(CASE WHEN brand IS NULL THEN 1 ELSE 0 END) AS null_brand,
    SUM(CASE WHEN user_session IS NULL THEN 1 ELSE 0 END) AS null_user_session
FROM events;

/* ------------------------------------------------------------
[4단계] 중복 데이터 점검
설명:
 - 동일 시간대 동일 유저·상품·이벤트 조합이 여러 번 기록되었는지 확인
------------------------------------------------------------ */
SELECT 
	event_time, user_id, product_id, event_type, count(*) AS duplicate_count
FROM events
GROUP BY event_time, user_id, product_id, event_type 
HAVING count(*) > 1;


/* ------------------------------------------------------------
[4-1단계] 결측치 및 중복 데이터 제거
설명:
 - user_session 결측 데이터 제거 (세션 단위 분석 불가)
 - DISTINCT로 중복 행 제거
------------------------------------------------------------ */
CREATE TABLE events_clean AS
SELECT DISTINCT *
FROM events
WHERE user_session IS NOT NULL;




/* ------------------------------------------------------------
[5단계] 세션 단위 정렬 테이블 생성
설명:
 - 세션별 이벤트를 시간순으로 정렬
 - 이후 퍼널 분석에 활용
------------------------------------------------------------ */
CREATE TABLE events_sorted AS
SELECT 
	user_id,
	user_session,
	event_time,
	event_type,
	product_id,
	category_code,
	price
FROM events_clean
ORDER BY user_id, user_session, event_time;

SELECT *
FROM events_sorted;

/* ------------------------------------------------------------
[6단계] 세션별 퍼널 요약 테이블 생성
설명:
 - 각 세션 내에서 행동별(view/cart/purchase) 발생 횟수를 집계
 - 이후 전환율 계산의 기반 데이터
------------------------------------------------------------ */

/* 세션 단위 퍼널 데이터 생성 */
CREATE TABLE session_funnel AS
SELECT
    user_session,
    COUNT(CASE WHEN event_type = 'view' THEN 1 END)     AS view_count,
    COUNT(CASE WHEN event_type = 'cart' THEN 1 END)     AS cart_count,
    COUNT(CASE WHEN event_type = 'purchase' THEN 1 END) AS purchase_count
FROM events_sorted
GROUP BY user_session;

SELECT *
FROM session_funnel;

/* ------------------------------------------------------------
[7단계] 단계별 전환율 계산
설명:
 - 전체 세션 기준으로 view→cart, view→purchase, cart→purchase 비율 계산
------------------------------------------------------------ */
SELECT
    COUNT(*) AS total_sessions,
    ROUND(SUM(CASE WHEN cart_count > 0 THEN 1 ELSE 0 END) * 1.0 / COUNT(*), 4) AS view_to_cart_rate,
    ROUND(SUM(CASE WHEN purchase_count > 0 THEN 1 ELSE 0 END) * 1.0 / COUNT(*), 4) AS view_to_purchase_rate,
    ROUND(SUM(CASE WHEN purchase_count > 0 AND cart_count > 0 THEN 1 ELSE 0 END) * 1.0 / SUM(CASE WHEN cart_count > 0 THEN 1 ELSE 0 END), 4) AS cart_to_purchase_rate
FROM session_funnel;


/* ------------------------------------------------------------
[7-1단계] 전환 단계별 요약 뷰 추가 (시각화용)
설명:
 - session_funnel 테이블을 기반으로 전환율을 요약한 뷰 생성
 - 이후 파이썬에서 시각화 시, 이 뷰를 직접 불러와 그래프로 표현 가능
------------------------------------------------------------ */
CREATE VIEW funnel_summary AS
SELECT
    'View → Cart' AS stage,
    ROUND(SUM(CASE WHEN cart_count > 0 THEN 1 ELSE 0 END) * 1.0 / COUNT(*), 4) AS conversion_rate
FROM session_funnel
UNION ALL
SELECT
    'Cart → Purchase',
    ROUND(SUM(CASE WHEN purchase_count > 0 AND cart_count > 0 THEN 1 ELSE 0 END) * 1.0 / 
          SUM(CASE WHEN cart_count > 0 THEN 1 ELSE 0 END), 4)
FROM session_funnel;

/* ------------------------------------------------------------
[7-2단계] 퍼널 요약 결과 확인
설명:
 - 앞서 만든 funnel_summary 뷰의 결과를 확인하여
   SQL 레벨에서 전환율 계산이 잘 되었는지 검증
------------------------------------------------------------ */
SELECT *
FROM funnel_summary;

/* ------------------------------------------------------------
[7-3단계] 세션별 행동 패턴 샘플 확인
설명:
 - 실제 세션 하나를 무작위로 선택해
   어떤 순서로 행동이 발생했는지 점검 (퍼널 정상 작동 확인)
------------------------------------------------------------ */
SELECT *
FROM events_sorted
WHERE user_session IN (
    SELECT user_session
    FROM session_funnel
    ORDER BY RANDOM()
    LIMIT 1
)
ORDER BY event_time;

/* ------------------------------------------------------------
[8단계] 세션 단위 퍼널 데이터 CSV로 내보내기
------------------------------------------------------------ */
COPY session_funnel
TO '/Users/hansol/Documents/data_projects/1.ecommerce_funnel_abtest/data/session_funnel.csv'
(HEADER, DELIMITER ',');

/* ------------------------------------------------------------
[마무리 안내]
이 SQL 스크립트는 EDA 및 퍼널 데이터 구축 단계를 포함하며,
이후 Python Notebook에서 다음 분석을 수행합니다:
  ▶ A/B 그룹 분리 및 전환율 비교
  ▶ 통계 검정 (z-test, t-test)
  ▶ 시각화 및 리포트 생성
============================================================ */
