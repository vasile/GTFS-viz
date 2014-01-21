CREATE TABLE agency (
    agency_id TEXT PRIMARY KEY,
    agency_name TEXT,
    agency_url TEXT,
    agency_timezone TEXT,
    agency_lang TEXT,
    agency_phone TEXT,
    agency_fare_url TEXT
);

CREATE TABLE stops (
    stop_id TEXT PRIMARY KEY,
    stop_code TEXT,
    stop_name TEXT,
    stop_desc TEXT,
    stop_lat REAL,
    stop_lon REAL,
    zone_id TEXT,
    stop_url TEXT,
    location_type INTEGER,
    parent_station TEXT,
    stop_timezone TEXT,
    wheelchair_boarding TEXT
);

CREATE TABLE routes (
    route_id TEXT PRIMARY KEY,
    agency_id TEXT,
    route_short_name TEXT,
    route_long_name TEXT,
    route_desc TEXT,
    route_type INTEGER,
    route_url TEXT,
    route_color TEXT,
    route_text_color TEXT
);
CREATE INDEX agency_id ON routes(agency_id);

CREATE TABLE trips (
    route_id TEXT,
    service_id TEXT,
    trip_id TEXT PRIMARY KEY,
    trip_headsign TEXT,
    trip_short_name TEXT,
    direction_id INTEGER,
    block_id TEXT,
    shape_id TEXT,
    wheelchair_accessible INTEGER,
    trip_ok INTEGER,
    trip_start_seconds INTEGER,
    trip_end_seconds INTEGER,
    trip_span_midnight INTEGER
);
CREATE INDEX route_id ON trips(route_id);
CREATE INDEX service_id ON trips(service_id);

CREATE TABLE stop_times (
    trip_id TEXT,
    arrival_time TEXT,
    departure_time TEXT,
    stop_id TEXT,
    stop_sequence INTEGER,
    stop_headsign TEXT,
    pickup_type INTEGER,
    drop_off_type INTEGER,
    shape_dist_traveled REAL,
    stop_shape_percent REAL
);
CREATE INDEX trip_id ON stop_times(trip_id);
CREATE INDEX stop_id ON stop_times(stop_id);
CREATE INDEX stop_times_id ON stop_times(trip_id, stop_id);

CREATE TABLE calendar (
    service_id TEXT PRIMARY KEY,
    monday INTEGER,
    tuesday INTEGER,
    wednesday INTEGER,
    thursday INTEGER,
    friday INTEGER,
    saturday INTEGER,
    sunday INTEGER,
    start_date TEXT,
    end_date TEXT
);
CREATE INDEX monday ON calendar(monday);
CREATE INDEX tuesday ON calendar(tuesday);
CREATE INDEX wednesday ON calendar(monday);
CREATE INDEX thursday ON calendar(thursday);
CREATE INDEX friday ON calendar(friday);
CREATE INDEX saturday ON calendar(saturday);
CREATE INDEX sunday ON calendar(sunday);

CREATE TABLE calendar_dates (
    service_id TEXT,
    date TEXT,
    exception_type INTEGER
);