-- UCSD Triton Transit Evening Service Gap Diagnosis & Schedule Optimization
-- SQL analysis script
-- Engine: DuckDB SQL
--
-- Note:
-- This script assumes GTFS raw files are placed locally under:
-- data/raw/current_gtfs/
--
-- The raw GTFS files are not required to be committed to GitHub.
-- They can be downloaded from the UCSD Triton Transit GTFS static feed.


-- ============================================================
-- 1. Load GTFS tables
-- ============================================================

CREATE OR REPLACE VIEW routes AS
SELECT *
FROM read_csv_auto('data/raw/current_gtfs/routes.txt');

CREATE OR REPLACE VIEW trips AS
SELECT *
FROM read_csv_auto('data/raw/current_gtfs/trips.txt');

CREATE OR REPLACE VIEW stop_times AS
SELECT *
FROM read_csv_auto('data/raw/current_gtfs/stop_times.txt');

CREATE OR REPLACE VIEW stops AS
SELECT *
FROM read_csv_auto('data/raw/current_gtfs/stops.txt');

CREATE OR REPLACE VIEW calendar AS
SELECT *
FROM read_csv_auto('data/raw/current_gtfs/calendar.txt');

CREATE OR REPLACE VIEW calendar_dates AS
SELECT *
FROM read_csv_auto('data/raw/current_gtfs/calendar_dates.txt');


-- ============================================================
-- 2. Convert GTFS time to minutes
-- ============================================================
-- GTFS time is stored as HH:MM:SS.
-- This step converts arrival_time into minutes after midnight.
-- Example: 17:30:00 -> 1050 minutes.

CREATE OR REPLACE VIEW stop_times_clean AS
SELECT
    trip_id,
    arrival_time,
    departure_time,
    stop_id,
    stop_sequence,
    CASE
        WHEN arrival_time IS NULL OR arrival_time = '' THEN NULL
        ELSE
            CAST(split_part(arrival_time, ':', 1) AS INTEGER) * 60
            + CAST(split_part(arrival_time, ':', 2) AS INTEGER)
            + CAST(split_part(arrival_time, ':', 3) AS DOUBLE) / 60
    END AS arrival_min
FROM stop_times;


-- ============================================================
-- 3. Build trip-level time summary
-- ============================================================
-- For each trip, identify its start time and end time.
-- These fields are used for route-level service analysis.

CREATE OR REPLACE VIEW trip_time_summary AS
SELECT
    trip_id,
    MIN(arrival_min) AS trip_start_min,
    MAX(arrival_min) AS trip_end_min,
    COUNT(arrival_min) AS timepoint_count,
    CAST(FLOOR(MIN(arrival_min) / 60) AS INTEGER) AS trip_start_hour,
    CAST(FLOOR(MAX(arrival_min) / 60) AS INTEGER) AS trip_end_hour
FROM stop_times_clean
WHERE arrival_min IS NOT NULL
GROUP BY trip_id;


-- ============================================================
-- 4. Build trip-level service table
-- ============================================================
-- Join trips with route information and trip start/end time.

CREATE OR REPLACE VIEW trip_service_master AS
SELECT
    t.trip_id,
    t.route_id,
    t.service_id,
    t.trip_headsign,
    t.direction_id,
    r.route_short_name,
    r.route_long_name,
    CONCAT(
        COALESCE(CAST(r.route_short_name AS VARCHAR), ''),
        ' - ',
        COALESCE(CAST(r.route_long_name AS VARCHAR), '')
    ) AS route_name,
    ts.trip_start_min,
    ts.trip_end_min,
    ts.trip_start_hour,
    ts.trip_end_hour,
    CASE
        WHEN ts.trip_start_hour BETWEEN 17 AND 21 THEN 1
        ELSE 0
    END AS is_evening_trip
FROM trips t
LEFT JOIN trip_time_summary ts
    ON t.trip_id = ts.trip_id
LEFT JOIN routes r
    ON t.route_id = r.route_id;


-- ============================================================
-- 5. Filter normal weekday service
-- ============================================================
-- Main analysis focuses on normal weekday service.

CREATE OR REPLACE VIEW weekday_trips AS
SELECT *
FROM trip_service_master
WHERE service_id = 'Weekday';


-- ============================================================
-- 6. Hourly service frequency
-- ============================================================
-- This table shows scheduled trip count by start hour.

CREATE OR REPLACE VIEW hourly_service_frequency_weekday AS
SELECT
    trip_start_hour,
    COUNT(DISTINCT trip_id) AS hourly_service_frequency,
    60.0 / COUNT(DISTINCT trip_id) AS estimated_headway_min,
    CASE
        WHEN trip_start_hour BETWEEN 17 AND 21 THEN 1
        ELSE 0
    END AS is_evening_hour
FROM weekday_trips
WHERE trip_start_hour IS NOT NULL
GROUP BY trip_start_hour
ORDER BY trip_start_hour;


-- ============================================================
-- 7. Evening hour gap ranking
-- ============================================================
-- Identify which evening hour has the lowest scheduled service supply.

CREATE OR REPLACE VIEW evening_hour_gap_ranking AS
SELECT
    CONCAT(
        LPAD(CAST(trip_start_hour AS VARCHAR), 2, '0'),
        ':00-',
        LPAD(CAST(trip_start_hour + 1 AS VARCHAR), 2, '0'),
        ':00'
    ) AS hour_range,
    trip_start_hour,
    hourly_service_frequency,
    estimated_headway_min
FROM hourly_service_frequency_weekday
WHERE is_evening_hour = 1
ORDER BY hourly_service_frequency ASC;


-- ============================================================
-- 8. Route-level service summary
-- ============================================================
-- Calculate total trips, evening trips, evening service share,
-- first trip time, last trip time, and service span by route.

CREATE OR REPLACE VIEW route_service_summary_weekday AS
SELECT
    route_id,
    route_name,
    COUNT(DISTINCT trip_id) AS total_trips,
    SUM(is_evening_trip) AS evening_trips,
    SUM(is_evening_trip) * 1.0 / COUNT(DISTINCT trip_id) AS evening_service_share,
    MIN(trip_start_min) AS first_trip_min,
    MAX(trip_start_min) AS last_trip_min,
    (MAX(trip_start_min) - MIN(trip_start_min)) / 60.0 AS service_span_hours,
    CASE
        WHEN SUM(is_evening_trip) > 0 THEN 300.0 / SUM(is_evening_trip)
        ELSE NULL
    END AS estimated_evening_headway_min,
    CONCAT(
        LPAD(CAST(FLOOR(MIN(trip_start_min) / 60) AS VARCHAR), 2, '0'),
        ':',
        LPAD(CAST(CAST(MIN(trip_start_min) AS INTEGER) % 60 AS VARCHAR), 2, '0')
    ) AS first_trip_time,
    CONCAT(
        LPAD(CAST(FLOOR(MAX(trip_start_min) / 60) AS VARCHAR), 2, '0'),
        ':',
        LPAD(CAST(CAST(MAX(trip_start_min) AS INTEGER) % 60 AS VARCHAR), 2, '0')
    ) AS last_trip_time
FROM weekday_trips
WHERE trip_start_min IS NOT NULL
GROUP BY route_id, route_name
ORDER BY estimated_evening_headway_min DESC;


-- ============================================================
-- 9. Route-hour service frequency
-- ============================================================
-- This table supports route-hour heatmap analysis.

CREATE OR REPLACE VIEW route_evening_hourly_service_weekday AS
SELECT
    route_id,
    route_name,
    trip_start_hour,
    COUNT(DISTINCT trip_id) AS hourly_trips,
    60.0 / COUNT(DISTINCT trip_id) AS estimated_headway_min
FROM weekday_trips
WHERE trip_start_hour BETWEEN 17 AND 21
GROUP BY route_id, route_name, trip_start_hour
ORDER BY route_name, trip_start_hour;


-- ============================================================
-- 10. Route-level Evening Service Gap Score
-- ============================================================
-- Composite score:
-- 40% headway score
-- 35% early last trip score
-- 25% low evening service share score

CREATE OR REPLACE VIEW route_gap_score_base AS
SELECT
    *,
    CASE
        WHEN MAX(estimated_evening_headway_min) OVER () = MIN(estimated_evening_headway_min) OVER ()
        THEN 0
        ELSE
            (estimated_evening_headway_min - MIN(estimated_evening_headway_min) OVER ())
            / NULLIF(
                MAX(estimated_evening_headway_min) OVER () - MIN(estimated_evening_headway_min) OVER (),
                0
            )
    END AS headway_score,

    LEAST(
        GREATEST((22 * 60 - last_trip_min) / 120.0, 0),
        1
    ) AS early_last_trip_score,

    1 -
    CASE
        WHEN MAX(evening_service_share) OVER () = MIN(evening_service_share) OVER ()
        THEN 0
        ELSE
            (evening_service_share - MIN(evening_service_share) OVER ())
            / NULLIF(
                MAX(evening_service_share) OVER () - MIN(evening_service_share) OVER (),
                0
            )
    END AS low_evening_share_score
FROM route_service_summary_weekday;


CREATE OR REPLACE VIEW route_evening_gap_score_weekday AS
SELECT
    route_id,
    route_name,
    total_trips,
    evening_trips,
    evening_service_share,
    estimated_evening_headway_min,
    first_trip_time,
    last_trip_time,
    service_span_hours,
    headway_score,
    early_last_trip_score,
    low_evening_share_score,
    0.40 * headway_score
        + 0.35 * early_last_trip_score
        + 0.25 * low_evening_share_score AS evening_gap_score
FROM route_gap_score_base
ORDER BY evening_gap_score DESC;


-- ============================================================
-- 11. Stop-level service summary
-- ============================================================
-- This SQL version uses trip start hour as an approximation
-- for stop-level evening coverage.
-- More detailed stop-level time interpolation is handled in Python.

CREATE OR REPLACE VIEW stop_service_master AS
SELECT
    st.trip_id,
    st.stop_id,
    s.stop_name,
    s.stop_lat,
    s.stop_lon,
    t.route_id,
    t.route_name,
    t.service_id,
    t.trip_start_hour,
    CASE
        WHEN t.trip_start_hour BETWEEN 17 AND 21 THEN 1
        ELSE 0
    END AS is_evening_stop_visit
FROM stop_times st
LEFT JOIN stops s
    ON st.stop_id = s.stop_id
LEFT JOIN trip_service_master t
    ON st.trip_id = t.trip_id;


CREATE OR REPLACE VIEW stop_service_summary_weekday AS
SELECT
    stop_id,
    stop_name,
    stop_lat,
    stop_lon,
    COUNT(*) AS total_visits,
    SUM(is_evening_stop_visit) AS evening_visits,
    SUM(is_evening_stop_visit) * 1.0 / COUNT(*) AS evening_coverage_rate,
    STRING_AGG(DISTINCT route_name, ', ') AS routes_serving_stop
FROM stop_service_master
WHERE service_id = 'Weekday'
GROUP BY stop_id, stop_name, stop_lat, stop_lon
ORDER BY evening_coverage_rate ASC, total_visits DESC;


-- ============================================================
-- 12. Export examples
-- ============================================================
-- Uncomment these lines when running locally in DuckDB
-- to export analysis outputs as CSV files.

-- COPY hourly_service_frequency_weekday
-- TO 'outputs/sql_hourly_service_frequency_weekday.csv'
-- (HEADER, DELIMITER ',');

-- COPY evening_hour_gap_ranking
-- TO 'outputs/sql_evening_hour_gap_ranking.csv'
-- (HEADER, DELIMITER ',');

-- COPY route_service_summary_weekday
-- TO 'outputs/sql_route_service_summary_weekday.csv'
-- (HEADER, DELIMITER ',');

-- COPY route_evening_gap_score_weekday
-- TO 'outputs/sql_route_evening_gap_score_weekday.csv'
-- (HEADER, DELIMITER ',');

-- COPY route_evening_hourly_service_weekday
-- TO 'outputs/sql_route_evening_hourly_service_weekday.csv'
-- (HEADER, DELIMITER ',');

-- COPY stop_service_summary_weekday
-- TO 'outputs/sql_stop_service_summary_weekday.csv'
-- (HEADER, DELIMITER ',');
