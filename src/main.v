// v-http-apilab: a deterministic synthetic HTTP API simulator.
//
// Every response is derived from fixed synthetic in-memory data; running
// the binary is enough to have the API answering on the configured port.
module main

import config
import logging
import router
import seed
import state
import veb
import infra
import auth
import users
import search
import reports
import tickets
import forms
import webhooks
import admin
import files
import lab
import metrics
import openapi
import os

fn register_routes(mut app router.App) {
	app.register(.get, '/', infra.index)
	app.register(.get, '/health', infra.health)
	app.register(.get, '/ready', infra.ready)
	app.register(.get, '/version', infra.version)
	app.register(.get, '/metrics', metrics.prometheus)
	app.register(.get, '/openapi.json', openapi.spec_json)
	app.register(.get, '/docs', openapi.swagger_ui)
	app.register(.post, '/api/v1/auth/login', auth.login)
	app.register(.post, '/api/v1/auth/logout', auth.logout)
	app.register(.get, '/api/v1/auth/me', auth.me)
	app.register(.get, '/api/v1/users', users.index)
	app.register(.get, '/api/v1/users/:id', users.show)
	app.register(.post, '/api/v1/users', users.create)
	app.register(.put, '/api/v1/users/:id', users.replace)
	app.register(.patch, '/api/v1/users/:id', users.update)
	app.register(.delete, '/api/v1/users/:id', users.destroy)
	app.register(.get, '/api/v1/search', search.search)
	app.register(.get, '/api/v1/reports', reports.index)
	app.register(.post, '/api/v1/reports/export', reports.export)
	app.register(.get, '/api/v1/reports/:id/download', reports.download)
	app.register(.post, '/api/v1/tickets', tickets.create)
	app.register(.get, '/api/v1/tickets/:id', tickets.show)
	app.register(.post, '/api/v1/forms/feedback', forms.feedback)
	app.register(.post, '/api/v1/webhooks/receive', webhooks.receive)
	app.register(.post, '/api/v1/graphql', webhooks.graphql)
	app.register(.post, '/api/v1/files/upload', files.upload)
	app.register(.get, '/static/:name', files.static_file)
	app.register(.get, '/admin/status', admin.status)
	app.register(.post, '/admin/config', admin.config)
	app.register(.get, '/internal/debug', admin.debug)
	app.register(.get, '/lab/echo', lab.echo)
	app.register(.get, '/lab/method', lab.method)
	app.register(.head, '/lab/method', lab.method)
	app.register(.post, '/lab/method', lab.method)
	app.register(.put, '/lab/method', lab.method)
	app.register(.patch, '/lab/method', lab.method)
	app.register(.delete, '/lab/method', lab.method)
	app.register(.options, '/lab/method', lab.method)
	app.register(.get, '/lab/slow', lab.slow)
	app.register(.get, '/lab/status/:code', lab.status_code)
	app.register(.get, '/lab/response-marker', lab.response_marker)
	app.register(.get, '/lab/large', lab.large)
	app.register(.get, '/lab/headers', lab.headers)
	app.register(.get, '/lab/stream', lab.stream)
	app.register(.get, '/lab/calls', lab.calls)
	app.register(.post, '/lab/calls/reset', lab.calls_reset)
}

// exit_on_signal makes SIGTERM/SIGINT end the process: as PID 1 in a
// container the kernel ignores signals that have no handler, so
// `docker stop` would otherwise wait for its SIGKILL timeout.
fn exit_on_signal(_ os.Signal) {
	exit(0)
}

fn main() {
	os.signal_opt(.term, exit_on_signal) or {}
	os.signal_opt(.int, exit_on_signal) or {}
	conf := config.load() or {
		eprintln('v-http-apilab: invalid configuration: ${err}')
		exit(1)
	}
	logger := logging.new()
	st := state.new(conf)
	mut app := &router.App{}
	app.setup(conf, st, logger)
	app.use(handler: app.request_middleware)
	register_routes(mut app)
	logger.write_event('info', 'v-http-apilab ${seed.app_version} starting on 0.0.0.0:${conf.port}')
	veb.run_at[router.App, router.Context](mut app,
		host:                      ''
		family:                    .ip
		port:                      conf.port
		timeout_in_seconds:        conf.read_timeout_seconds()
		max_request_buffer_size:   16384
		benchmark_page_generation: true
		show_startup_message:      false
	) or {
		eprintln('v-http-apilab: server failed to start: ${err}')
		exit(1)
	}
}
