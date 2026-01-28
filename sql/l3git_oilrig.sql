CREATE TABLE IF NOT EXISTS l3git_oilrig_state (
    rig_id VARCHAR(64) NOT NULL,
    fuel_cans INT NOT NULL DEFAULT 0,
    is_running TINYINT(1) NOT NULL DEFAULT 0,
    start_time BIGINT NOT NULL DEFAULT 0,
    end_time BIGINT NOT NULL DEFAULT 0,
    barrels_ready INT NOT NULL DEFAULT 0,
    last_fuel_used INT NOT NULL DEFAULT 0,
    updated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    PRIMARY KEY (rig_id)
);

CREATE TABLE IF NOT EXISTS l3git_oilrig_names (
    identifier VARCHAR(96) NOT NULL,
    rig_id VARCHAR(64) NOT NULL,
    rig_name VARCHAR(64) NOT NULL,
    updated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    PRIMARY KEY (identifier, rig_id)
);
