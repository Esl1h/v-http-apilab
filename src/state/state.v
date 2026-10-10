// state owns all shared mutable in-memory state behind a single mutex.
//
// The veb fasthttp backend serves requests from several worker threads
// on one shared App, so every mutable structure lives here and every
// access goes through a locking method. Restarting the process restores
// the seed state: there is no database and nothing is persisted.
module state

import config
import seed
import sync
import time

pub struct State {
mut:
	mu        &sync.Mutex = unsafe { nil }
	conf      config.Config
	started   time.Time
	users     []seed.User
	next_uid  int
	tickets   []seed.Ticket
	next_tid  int
	sessions  map[string]Session
	jobs      []ExportJob
	next_jid  int
	metrics   map[string]map[string]int
	req_total i64
	calls     []CallRecord
}

pub struct Session {
pub:
	username     string
	expires_unix i64
}

pub struct ExportJob {
pub:
	job_id    string
	report_id string
	format    string
	created   string
}

pub const calls_capacity = 200

// new builds the initial state from configuration and the synthetic seed.
pub fn new(conf config.Config) &State {
	mut s := &State{
		conf:     conf
		started:  time.now()
		users:    seed.users()
		next_uid: 26
		tickets:  seed.tickets()
		next_tid: 4
		sessions: map[string]Session{}
		jobs:     []ExportJob{}
		next_jid: 1
		metrics:  map[string]map[string]int{}
		calls:    []CallRecord{}
	}
	s.mu = sync.new_mutex()
	return s
}

// config returns the configuration snapshot taken at startup.
pub fn (s &State) config() config.Config {
	s.mu.lock()
	c := s.conf
	s.mu.unlock()
	return c
}

// uptime_seconds returns seconds since process start.
pub fn (s &State) uptime_seconds() i64 {
	s.mu.lock()
	up := time.now().unix() - s.started.unix()
	s.mu.unlock()
	return up
}

// started_at returns the RFC3339 start timestamp.
pub fn (s &State) started_at() string {
	s.mu.lock()
	at := s.started.format_rfc3339()
	s.mu.unlock()
	return at
}
