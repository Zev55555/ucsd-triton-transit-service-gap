
# Data Dictionary

## Project Dataset

This project uses the latest UCSD Triton Transit GTFS static feed. GTFS is a public transit data format that contains route, trip, stop, and schedule information.

## Raw GTFS Tables

### agency.txt
Transit agency information.

Important fields:
- `agency_id`: agency identifier
- `agency_name`: transit agency name
- `agency_url`: agency website
- `agency_timezone`: agency timezone

### routes.txt
Route-level information.

Important fields:
- `route_id`: route identifier
- `route_short_name`: short route name
- `route_long_name`: full route name
- `route_desc`: route description
- `route_type`: type of transit route

### trips.txt
Trip-level information.

Important fields:
- `route_id`: route identifier
- `service_id`: service calendar identifier
- `trip_id`: trip identifier
- `trip_headsign`: trip destination or direction
- `direction_id`: direction of travel

### stop_times.txt
Stop sequence and scheduled arrival/departure information for each trip.

Important fields:
- `trip_id`: trip identifier
- `arrival_time`: scheduled arrival time
- `departure_time`: scheduled departure time
- `stop_id`: stop identifier
- `stop_sequence`: stop order within a trip

### stops.txt
Stop-level information.

Important fields:
- `stop_id`: stop identifier
- `stop_name`: stop name
- `stop_lat`: stop latitude
- `stop_lon`: stop longitude

### calendar.txt
Regular service calendar.

Important fields:
- `service_id`: service calendar identifier
- `monday` to `sunday`: service availability by weekday
- `start_date`: service start date
- `end_date`: service end date

### calendar_dates.txt
Special service date exceptions.

Important fields:
- `service_id`: service calendar identifier
- `date`: exception date
- `exception_type`: added or removed service

## Processed Tables

### gtfs_service_master.csv
Joined stop-level GTFS table created from `stop_times`, `trips`, `routes`, and `stops`.

### hourly_service_frequency_weekday.csv
Hourly scheduled trip counts for normal weekday service.

### route_service_summary_weekday.csv
Route-level service summary, including total trips, evening trips, evening service share, first trip time, last trip time, and service span.

### route_evening_gap_score_weekday.csv
Route-level Evening Service Gap Score table.

### stop_evening_gap_score_weekday.csv
Stop-level evening coverage gap score table.

### route_optimization_simulation.csv
Simulated schedule optimization table comparing current evening service and recommended adjusted service.

## Key Metrics

### hourly_service_frequency
Number of scheduled trips starting in each hour.

### estimated_headway_min
Estimated average headway in minutes. It is calculated as:

`60 / hourly_service_frequency`

For route-level evening analysis, it is calculated as:

`300 / evening_trips`

because the evening window is 17:00-22:00, or 5 hours.

### evening_service_share
Share of a route's total weekday trips that occur during the evening window.

### last_trip_time
The last scheduled trip start time for a route.

### service_span_hours
Difference between first scheduled trip and last scheduled trip.

### stop_evening_coverage_rate
Share of a stop's total weekday visits that occur during the evening window.

### Evening Service Gap Score
A composite route-level score used to prioritize schedule optimization.

It combines:
- headway score
- early last trip score
- low evening service share score

Higher score means higher evening service gap.
