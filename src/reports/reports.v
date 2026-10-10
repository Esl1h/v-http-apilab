// reports: synthetic report listing, export jobs and CSV download.
module reports

import router
import seed
import strings
import veb

pub struct ReportsBody {
pub:
	count int           @[json: 'count']
	items []seed.Report @[json: 'items']
}

// index lists the fixed synthetic report catalog.
pub fn index(mut app router.App, mut ctx router.Context, params []string) veb.Result {
	_ = params
	items := seed.reports()
	return ctx.respond_json(.ok, ReportsBody{
		count: items.len
		items: items
	})
}

pub struct ExportRequest {
pub mut:
	report_id string @[json: 'report_id']
	format    string @[json: 'format']
}

pub struct ExportBody {
pub:
	job_id     string @[json: 'job_id']
	status     string @[json: 'status']
	report_id  string @[json: 'report_id']
	format     string @[json: 'format']
	request_id string @[json: 'request_id']
}

// export validates the request and queues a synthetic job (nothing
// actually runs; the job list is inspectable via /internal/debug).
pub fn export(mut app router.App, mut ctx router.Context, params []string) veb.Result {
	_ = params
	if !ctx.require_json() {
		return veb.no_result()
	}
	body := ctx.parse_body[ExportRequest]() or {
		return ctx.respond_error(.bad_request, 'invalid_json', 'request body is not valid JSON: ${err}')
	}
	if body.report_id == '' || body.format == '' {
		return ctx.respond_error(.unprocessable_entity, 'validation_error',
			'both "report_id" and "format" are required')
	}
	def := seed.report_by_id(body.report_id) or {
		return ctx.respond_error(.not_found, 'not_found', 'report ${body.report_id} not found')
	}
	if body.format !in ['csv', 'json'] {
		return ctx.respond_error(.unprocessable_entity, 'validation_error',
			'"format" must be one of csv, json, got "${body.format}"')
	}
	mut st := app.store()
	job := st.job_add(def.id, body.format)
	return ctx.respond_json(.accepted, ExportBody{
		job_id:     job.job_id
		status:     'queued'
		report_id:  job.report_id
		format:     job.format
		request_id: ctx.request_id
	})
}

// csv_quote quotes one CSV field when needed.
fn csv_quote(field string) string {
	if field.contains(',') || field.contains('"') || field.contains('\n') {
		return '"${field.replace('"', '""')}"'
	}
	return field
}

// download streams the synthetic CSV content of a report.
pub fn download(mut app router.App, mut ctx router.Context, params []string) veb.Result {
	def := seed.report_by_id(params[0]) or {
		return ctx.respond_error(.not_found, 'not_found', 'report ${params[0]} not found')
	}
	mut sb := strings.new_builder(256)
	sb.write_string('region,label,value\n')
	for row in 1 .. def.rows + 1 {
		region := csv_quote('Region ${row}')
		sb.write_string('${region},synthetic_${def.id}_${row},${row * 7}\n')
	}
	body := sb.str()
	ctx.set_header(.content_disposition, 'attachment; filename="${def.id}.csv"')
	ctx.set_header(.content_type, 'text/csv')
	return ctx.text(body)
}
