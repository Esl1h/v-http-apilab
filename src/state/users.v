// users.v: user CRUD, tickets and synthetic auth sessions (module state).
module state

import rand
import seed
import time

// users_all returns a copy of the current user table.
pub fn (s &State) users_all() []seed.User {
	s.mu.lock()
	list := s.users.clone()
	s.mu.unlock()
	return list
}

// users_count returns the number of stored users.
pub fn (s &State) users_count() int {
	s.mu.lock()
	n := s.users.len
	s.mu.unlock()
	return n
}

// user_by_id returns the user with the given numeric id.
pub fn (s &State) user_by_id(id int) ?seed.User {
	s.mu.lock()
	defer {
		s.mu.unlock()
	}
	for u in s.users {
		if u.id == id {
			return u
		}
	}
	return none
}

// user_add appends a validated user and returns it with its new id.
pub fn (mut s State) user_add(name string, email string, department string, role string) seed.User {
	s.mu.lock()
	s.next_uid++
	u := seed.User{
		id:         s.next_uid - 1
		name:       name
		email:      email
		department: department
		role:       role
	}
	s.users << u
	s.mu.unlock()
	return u
}

// user_replace overwrites the whole record of an existing user.
pub fn (mut s State) user_replace(id int, name string, email string, department string, role string) ?seed.User {
	s.mu.lock()
	defer {
		s.mu.unlock()
	}
	for i, u in s.users {
		if u.id == id {
			s.users[i] = seed.User{
				id:         id
				name:       name
				email:      email
				department: department
				role:       role
			}
			return s.users[i]
		}
	}
	return none
}

// user_patch applies only the provided fields of an existing user.
pub fn (mut s State) user_patch(id int, patch map[string]string) ?seed.User {
	s.mu.lock()
	defer {
		s.mu.unlock()
	}
	for i, u in s.users {
		if u.id == id {
			// seed.User fields are immutable, so build a fresh record
			// with the patched values instead of mutating a copy.
			name := patch['name'] or { u.name }
			email := patch['email'] or { u.email }
			department := patch['department'] or { u.department }
			role := patch['role'] or { u.role }
			nu := seed.User{
				id:         u.id
				name:       name
				email:      email
				department: department
				role:       role
			}
			s.users[i] = nu
			return nu
		}
	}
	return none
}

// user_delete removes a user; returns false when the id is unknown.
pub fn (mut s State) user_delete(id int) bool {
	s.mu.lock()
	defer {
		s.mu.unlock()
	}
	for i, u in s.users {
		if u.id == id {
			s.users.delete(i)
			return true
		}
	}
	return false
}

// tickets_all returns a copy of the current ticket list.
pub fn (s &State) tickets_all() []seed.Ticket {
	s.mu.lock()
	list := s.tickets.clone()
	s.mu.unlock()
	return list
}

// ticket_by_id returns the ticket with the given numeric id.
pub fn (s &State) ticket_by_id(id int) ?seed.Ticket {
	s.mu.lock()
	defer {
		s.mu.unlock()
	}
	for t in s.tickets {
		if t.id == id {
			return t
		}
	}
	return none
}

// ticket_add appends a validated ticket and returns it with its new id.
pub fn (mut s State) ticket_add(title string, description string, severity string, tags []string) seed.Ticket {
	s.mu.lock()
	t := seed.Ticket{
		id:          s.next_tid
		title:       title
		description: description
		severity:    severity
		tags:        tags
	}
	s.next_tid++
	s.tickets << t
	s.mu.unlock()
	return t
}

// sessions_count returns the number of active synthetic sessions.
pub fn (s &State) sessions_count() int {
	s.mu.lock()
	n := s.sessions.len
	s.mu.unlock()
	return n
}

// session_create issues a synthetic opaque token for `username`.
pub fn (mut s State) session_create(username string, ttl_seconds i64) string {
	token := 'vhl-${rand.uuid_v4()}'
	now := time.now().unix()
	s.mu.lock()
	s.sessions[token] = Session{
		username:     username
		expires_unix: now + ttl_seconds
	}
	s.mu.unlock()
	return token
}

// session_lookup returns the username bound to a live token.
pub fn (mut s State) session_lookup(token string) ?string {
	s.mu.lock()
	session := s.sessions[token] or {
		s.mu.unlock()
		return none
	}
	expired := time.now().unix() > session.expires_unix
	username := session.username
	if expired {
		s.sessions.delete(token)
	}
	s.mu.unlock()
	if expired {
		return none
	}
	return username
}

// session_delete revokes a token; returns false when it did not exist.
pub fn (mut s State) session_delete(token string) bool {
	s.mu.lock()
	defer {
		s.mu.unlock()
	}
	if token !in s.sessions {
		return false
	}
	s.sessions.delete(token)
	return true
}

// jobs_all returns a copy of the issued synthetic export jobs.
pub fn (s &State) jobs_all() []ExportJob {
	s.mu.lock()
	list := s.jobs.clone()
	s.mu.unlock()
	return list
}

// jobs_count returns the number of issued export jobs.
pub fn (s &State) jobs_count() int {
	s.mu.lock()
	n := s.jobs.len
	s.mu.unlock()
	return n
}

// job_add records a deterministic export job ("job-N") and returns it.
pub fn (mut s State) job_add(report_id string, format string) ExportJob {
	now := time.now().format_rfc3339()
	s.mu.lock()
	job := ExportJob{
		job_id:    'job-${s.next_jid}'
		report_id: report_id
		format:    format
		created:   now
	}
	s.next_jid++
	s.jobs << job
	s.mu.unlock()
	return job
}
