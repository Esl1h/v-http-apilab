// config loads runtime settings from environment variables.
//
// Every knob of the lab is an env var so the same binary can be used to
// exercise different scenarios without rebuilding.
module config

import os
import strconv

// valid_log_levels are the accepted LOG_LEVEL values.
pub const valid_log_levels = ['debug', 'info', 'warn', 'error']

pub struct Config {
pub:
	port              int = 8080
	max_body_bytes    i64 = 1048576
	read_timeout_ms   i64 = 30000
	lab_admin_token   string
	ready_force_fail  bool
	log_level         string = 'info'
	max_slow_ms       int    = 10000
	max_large_bytes   i64    = 1048576
	auth_username     string = 'admin'
	auth_password     string = 'lab-password-123456'
	token_ttl_seconds i64    = 3600
}

// read_timeout_seconds maps READ_TIMEOUT_MS onto the granularity actually
// supported by veb's RunParams (whole seconds), with a 1s floor.
pub fn (c Config) read_timeout_seconds() int {
	secs := c.read_timeout_ms / 1000
	if secs < 1 {
		return 1
	}
	return int(secs)
}

fn env_str(key string, default string) string {
	val := os.getenv_opt(key) or { return default }
	return val
}

fn env_bool(key string) bool {
	val := os.getenv_opt(key) or { return false }
	return val != ''
}

fn env_int(key string, default int) !int {
	val := os.getenv_opt(key) or { return default }
	parsed := strconv.atoi(val) or { return error('must be an integer, got "${val}"') }
	return parsed
}

fn env_i64(key string, default i64) !i64 {
	val := os.getenv_opt(key) or { return default }
	parsed := strconv.parse_int(val, 10, 64) or { return error('must be an integer, got "${val}"') }
	return parsed
}

// load reads and validates all environment variables. It returns an error
// (instead of silently falling back) so a misconfigured lab fails loudly.
pub fn load() !Config {
	port := env_int('PORT', 8080) or { return error('PORT: ${err}') }
	if port < 1 || port > 65535 {
		return error('PORT: must be between 1 and 65535, got ${port}')
	}
	max_body_bytes := env_i64('MAX_BODY_BYTES', 1048576) or {
		return error('MAX_BODY_BYTES: ${err}')
	}
	if max_body_bytes < 1 {
		return error('MAX_BODY_BYTES: must be at least 1')
	}
	read_timeout_ms := env_i64('READ_TIMEOUT_MS', 30000) or {
		return error('READ_TIMEOUT_MS: ${err}')
	}
	if read_timeout_ms < 1000 {
		return error('READ_TIMEOUT_MS: must be at least 1000')
	}
	max_slow_ms := env_int('MAX_SLOW_MS', 10000) or { return error('MAX_SLOW_MS: ${err}') }
	if max_slow_ms < 1 {
		return error('MAX_SLOW_MS: must be at least 1')
	}
	max_large_bytes := env_i64('MAX_LARGE_BYTES', 1048576) or {
		return error('MAX_LARGE_BYTES: ${err}')
	}
	if max_large_bytes < 1 {
		return error('MAX_LARGE_BYTES: must be at least 1')
	}
	log_level := env_str('LOG_LEVEL', 'info').to_lower()
	if log_level !in valid_log_levels {
		return error('LOG_LEVEL: must be one of ${valid_log_levels.join(', ')}, got "${log_level}"')
	}
	return Config{
		port:              port
		max_body_bytes:    max_body_bytes
		read_timeout_ms:   read_timeout_ms
		lab_admin_token:   env_str('LAB_ADMIN_TOKEN', '')
		ready_force_fail:  env_bool('READY_FORCE_FAIL')
		log_level:         log_level
		max_slow_ms:       max_slow_ms
		max_large_bytes:   max_large_bytes
		auth_username:     env_str('LAB_USERNAME', 'admin')
		auth_password:     env_str('LAB_PASSWORD', 'lab-password-123456')
		token_ttl_seconds: 3600
	}
}
