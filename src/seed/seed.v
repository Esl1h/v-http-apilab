// seed holds 100% synthetic, deterministic datasets.
//
// Nothing here resembles real people, hosts or credentials: every name,
// email, report and document is generated or hand-written for the lab.
// The data is the same on every start, so a request blocked by an
// intermediary can be diffed against a request that reached the app.
module seed

pub const app_name = 'v-http-apilab'

pub const app_version = '1.0.1'

// v_version is baked in at build time. The build scripts export the
// output of `v version` before compiling, so /version and
// /internal/debug report the exact toolchain that produced the binary
// ("unknown" when not provided).
pub const v_version = $env('V_VERSION')

// response_marker is a fixed, harmless marker used by /lab/response-marker
// to test response-body inspection.
pub const response_marker = 'LAB_RESPONSE_MARKER_7f3a'

pub const departments = ['engineering', 'finance', 'operations', 'support', 'security']

pub const roles = ['admin', 'operator', 'viewer']

pub const severities = ['low', 'medium', 'high', 'critical']

pub struct User {
pub:
	id         int    @[json: 'id']
	name       string @[json: 'name']
	email      string @[json: 'email']
	department string @[json: 'department']
	role       string @[json: 'role']
}

// users builds the fixed synthetic user table (25 entries).
pub fn users() []User {
	mut list := []User{cap: 25}
	for i in 1 .. 26 {
		role := if i <= 2 {
			'admin'
		} else if i <= 12 {
			'operator'
		} else {
			'viewer'
		}
		list << User{
			id:         i
			name:       'Lab User ${i}'
			email:      'user${i}@lab.example'
			department: departments[(i - 1) % departments.len]
			role:       role
		}
	}
	return list
}

pub struct Report {
pub:
	report_id    string @[json: 'report_id']
	title        string @[json: 'title']
	category     string @[json: 'category']
	rows         int    @[json: 'rows']
	generated_at string @[json: 'generated_at']
}

pub struct ReportDef {
pub:
	id       string
	title    string
	category string
	rows     int
	when     string
}

// reports is the fixed synthetic report catalog (6 entries).
pub const report_defs = [
	ReportDef{
		id:       'rep-001'
		title:    'Monthly Sales Summary (synthetic)'
		category: 'sales'
		rows:     8
		when:     '2026-01-31T00:00:00Z'
	},
	ReportDef{
		id:       'rep-002'
		title:    'Quarterly Finance Overview (synthetic)'
		category: 'finance'
		rows:     10
		when:     '2026-01-15T00:00:00Z'
	},
	ReportDef{
		id:       'rep-003'
		title:    'Infrastructure Utilization (synthetic)'
		category: 'operations'
		rows:     12
		when:     '2026-02-05T00:00:00Z'
	},
	ReportDef{
		id:       'rep-004'
		title:    'Support Tickets by Severity (synthetic)'
		category: 'support'
		rows:     6
		when:     '2026-02-10T00:00:00Z'
	},
	ReportDef{
		id:       'rep-005'
		title:    'Security Audit Checklist (synthetic)'
		category: 'security'
		rows:     9
		when:     '2026-03-01T00:00:00Z'
	},
	ReportDef{
		id:       'rep-006'
		title:    'Employee Rotation Plan (synthetic)'
		category: 'hr'
		rows:     5
		when:     '2026-03-15T00:00:00Z'
	},
]

pub fn reports() []Report {
	mut list := []Report{cap: report_defs.len}
	for def in report_defs {
		list << Report{
			report_id:    def.id
			title:        def.title
			category:     def.category
			rows:         def.rows
			generated_at: def.when
		}
	}
	return list
}

pub fn report_by_id(id string) ?ReportDef {
	for def in report_defs {
		if def.id == id {
			return def
		}
	}
	return none
}

pub struct SearchDoc {
pub:
	id    string
	title string
}

// search_docs is the fixed synthetic document corpus (8 entries).
pub const search_docs = [
	SearchDoc{
		id:    'doc-01'
		title: 'Runbook: synthetic deployment pipeline'
	},
	SearchDoc{
		id:    'doc-02'
		title: 'Guide: synthetic incident rotation'
	},
	SearchDoc{
		id:    'doc-03'
		title: 'Policy: synthetic data retention'
	},
	SearchDoc{
		id:    'doc-04'
		title: 'Handbook: synthetic onboarding flow'
	},
	SearchDoc{
		id:    'doc-05'
		title: 'Reference: synthetic API limits'
	},
	SearchDoc{
		id:    'doc-06'
		title: 'Checklist: synthetic release review'
	},
	SearchDoc{
		id:    'doc-07'
		title: 'Notebook: synthetic capacity planning'
	},
	SearchDoc{
		id:    'doc-08'
		title: 'Memo: synthetic lab usage rules'
	},
]

pub struct Ticket {
pub:
	id          int      @[json: 'id']
	title       string   @[json: 'title']
	description string   @[json: 'description']
	severity    string   @[json: 'severity']
	tags        []string @[json: 'tags']
}

// tickets builds the fixed synthetic ticket seed (3 entries).
pub fn tickets() []Ticket {
	return [
		Ticket{
			id:          1
			title:       'Printer on floor 3 reports synthetic jam'
			description: 'Synthetic description for lab ticket 1.'
			severity:    'low'
			tags:        ['hardware', 'printer']
		},
		Ticket{
			id:          2
			title:       'Quarterly report export slower than usual'
			description: 'Synthetic description for lab ticket 2.'
			severity:    'medium'
			tags:        ['reports', 'performance']
		},
		Ticket{
			id:          3
			title:       'Suspicious synthetic login pattern flagged'
			description: 'Synthetic description for lab ticket 3.'
			severity:    'high'
			tags:        ['security', 'auth']
		},
	]
}

// StaticFile is one entry of the /static/{name} allowlist.
pub struct StaticFile {
pub:
	name         string
	content_type string
	body         string
}

// static_files is the complete allowlist served by /static/{name}.
// Anything not in this list answers 404; nothing is read from disk.
pub const static_files = [
	StaticFile{
		name:         'robots.txt'
		content_type: 'text/plain'
		body:         'User-agent: *\nDisallow: /admin/\nDisallow: /internal/\n# synthetic robots file for the lab\n'
	},
	StaticFile{
		name:         'style.css'
		content_type: 'text/css'
		body:         '/* synthetic stylesheet for the lab */\nbody { font-family: monospace; margin: 2rem; }\n.marker { display: none; }\n'
	},
	StaticFile{
		name:         'logo.svg'
		content_type: 'image/svg+xml'
		body:         '<svg xmlns="http://www.w3.org/2000/svg" width="64" height="64"><rect width="64" height="64" fill="#333"/><text x="8" y="40" font-size="20" fill="#eee">LAB</text></svg>\n'
	},
	StaticFile{
		name:         'data.csv'
		content_type: 'text/csv'
		body:         'id,label,value\n1,alpha,10\n2,beta,20\n3,gamma,30\n# synthetic dataset for response inspection\n'
	},
]

pub fn static_file_by_name(name string) ?StaticFile {
	for f in static_files {
		if f.name == name {
			return f
		}
	}
	return none
}
