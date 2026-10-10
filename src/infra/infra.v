// infra: health, readiness and version endpoints.
module infra

import router
import seed
import veb

pub struct IndexBody {
pub:
	name        string   @[json: 'name']
	version     string   @[json: 'version']
	description string   @[json: 'description']
	endpoints   []string @[json: 'endpoints']
}

pub fn index(mut app router.App, mut ctx router.Context, params []string) veb.Result {
	_ = params
	return ctx.respond_json(.ok, IndexBody{
		name:        seed.app_name
		version:     seed.app_version
		description: 'deterministic synthetic HTTP lab API'
		endpoints:   ['/health', '/ready', '/version', '/metrics', '/openapi.json', '/docs', '/lab/echo',
			'/lab/calls']
	})
}

pub struct HealthBody {
pub:
	status string @[json: 'status']
}

// health always answers 200 with status ok (liveness).
pub fn health(mut app router.App, mut ctx router.Context, params []string) veb.Result {
	_ = params
	return ctx.respond_json(.ok, HealthBody{
		status: 'ok'
	})
}

pub struct ReadyBody {
pub:
	status string @[json: 'status']
}

// ready answers 200 unless READY_FORCE_FAIL is set (readiness drill).
pub fn ready(mut app router.App, mut ctx router.Context, params []string) veb.Result {
	_ = params
	if app.cfg().ready_force_fail {
		return ctx.respond_json(.service_unavailable, ReadyBody{
			status: 'unavailable'
		})
	}
	return ctx.respond_json(.ok, ReadyBody{
		status: 'ready'
	})
}

pub struct VersionBody {
pub:
	app           string @[json: 'app']
	version       string @[json: 'version']
	v_version     string @[json: 'v_version']
	build_date    string @[json: 'build_date']
	deterministic bool   @[json: 'deterministic_seed']
}

// version reports the app version, the V toolchain version and the
// build date (reproducible via SOURCE_DATE_EPOCH).
pub fn version(mut app router.App, mut ctx router.Context, params []string) veb.Result {
	_ = params
	return ctx.respond_json(.ok, VersionBody{
		app:           seed.app_name
		version:       seed.app_version
		v_version:     seed.v_version
		build_date:    @BUILD_DATE
		deterministic: true
	})
}
