# Action options must be passed as a JSON string
#
# Format with example values:
#
# {
#   "bridgehub" => {
#     "api" => "http://localhost:8080/kinetic-bridgehub/app/manage-api/v1",
#     "server" => "http://localhost:8080/kinetic-bridgehub",
#     "space_slug" => "acme",
#     "bridges" => {
#       "kinetic-core" => {
#         "access_key_id" => "key",
#         "access_key_secret" => "secret",
#         "bridge_path" =>  "http://localhost:8080/kinetic-bridgehub/app/api/v1/bridges/#{space_slug}-core",
#         "slug" =>  "kinetic-core"
#       }
#     },
#   },
#   "core" => {
#     "api" => "http://localhost:8080/kinetic/app/api/v1",
#     "server" => "http://localhost:8080/kinetic",
#     "space_slug" => "foo",
#     "space_name" => "Foo",
#     "service_user_username" => "service_user_username",
#     "service_user_password" => "secret"
#   },
#   "discussions" => {
#     "api" => "http://localhost:8080/app/discussions/api/v1",
#     "server" => "http://localhost:8080/app/discussions",
#     "space_slug" => "foo"
#   },
#   "filehub" => {
#     "api" => "http://localhost:8080/kinetic-filehub/app/api/v1",
#     "server" => "http://localhost:8080/kinetic-filehub",
#     "space_slug" => "foo",
#     "filestores" => {
#       "kinetic-core" => {
#         "access_key_id" => "key",
#         "access_key_secret" => "secret",
#         "filestore_path" =>  "http://localhost:8080/kinetic-bridgehub/bridges/kinetic-core",
#         "slug" =>  "kinetic-core"
#       }
#     },
#   },
#   "task" => {
#     "api" => "http://localhost:8080/kinetic-task/app/api/v1",
#     "api_v2" => "http://localhost:8080/kinetic-task/app/api/v2",
#     "server" => "http://localhost:8080/kinetic-task",
#     "space_slug" => "foo",
#     "service_user_username" => "service_user_username",
#     "service_user_password" => "secret"
#   }
# }

require 'logger'
require 'json'

template_name = "platform-template-base"

logger = Logger.new(STDERR)
logger.level = Logger::INFO

raise "Missing JSON argument string passed to template export script" if ARGV.empty?
begin
  vars = JSON.parse(ARGV[0])
rescue => e
  raise "Template #{template_name} repair error: #{e.inspect}"
end


# determine the directory paths
platform_template_path = File.dirname(File.expand_path(__FILE__))
core_path = File.join(platform_template_path, "core")
task_path = File.join(platform_template_path, "task")

# ------------------------------------------------------------------------------
# constants
# ------------------------------------------------------------------------------

# Configuration of which submissions should be exported
SUBMISSIONS_TO_EXPORT = [
  {"datastore" => true, "formSlug" => "notification-data"},
  {"datastore" => true, "formSlug" => "notification-template-dates"}
]

REMOVE_DATA_PROPERTIES = [
  "createdAt",
  "createdBy",
  "updatedAt",
  "updatedBy",
  "closedAt",
  "closedBy",
  "submittedAt",
  "submittedBy",
  "id",
  "authStrategy",
  "key",
  "handle"
]

# ------------------------------------------------------------------------------
# setup
# ------------------------------------------------------------------------------

logger.info "Installing gems for the \"#{template_name}\" template."
Dir.chdir(platform_template_path) { system("bundle", "install") }

require 'kinetic_sdk'

# ------------------------------------------------------------------------------
# core
# ------------------------------------------------------------------------------

logger.info "Removing files and folders from the existing \"#{template_name}\" template."
FileUtils.rm_rf Dir.glob("#{core_path}/*")

logger.info "Setting up the Core SDK"
space_sdk = KineticSdk::Core.new({
  space_server_url: vars["core"]["server"],
  space_slug: vars["core"]["space_slug"],
  username: vars["core"]["service_user_username"],
  password: vars["core"]["service_user_password"],
  options: {
    export_directory: "#{core_path}",
  }
})

# Fetch Export from Core and write to files
logger.info "Exporting the core components for the \"#{template_name}\" template."
logger.info "  exporting with api: #{space_sdk.api_url}"
logger.info "   - exporting configuration data (Kapps,forms, etc)"
space_sdk.export_space

# Export Submissions
logger.info "  - exporting and writing submission data"
SUBMISSIONS_TO_EXPORT.each do |item|
  is_datastore = item["datastore"] || false
  logger.info "    - #{is_datastore ? 'datastore' : 'kapp'} form #{item['formSlug']}"
  # Build directory to write files to
  submission_path = is_datastore ?
    "#{core_path}/space/datastore/forms/#{item['formSlug']}" :
    "#{core_path}/kapps/#{item['kappSlug']}/forms/#{item['formSlug']}"

  # Create folder to write submission data to
  FileUtils.mkdir_p(submission_path, :mode => 0700)

  # Build params to pass to the retrieve_form_submissions method
  params = {"include" => "values", "limit" => 1000, "direction" => "ASC"}

  # Open the submissions file in write mode
  file = File.open("#{submission_path}/submissions.ndjson", 'w');

  # Ensure the file is empty
  file.truncate(0)
  response = nil
  begin
    # Get submissions
    response = is_datastore ?
      space_sdk.find_all_form_datastore_submissions(item['formSlug'], params).content :
      space_sdk.find_form_submissions(item['kappSlug'], item['formSlug'], params).content
    if response.has_key?("submissions")
      # Write each submission on its own line
      (response["submissions"] || []).each do |submission|
        # Append each submission (removing the submission unwanted attributes)
        file.puts(JSON.generate(submission.delete_if { |key, value| REMOVE_DATA_PROPERTIES.member?(key)}))
      end
    end
    params['pageToken'] = response['nextPageToken']
    # Get next page of submissions if there are more
  end while !response.nil? && !response['nextPageToken'].nil?
  # Close the submissions file
  file.close()
end
logger.info "  - submission data export complete"

# ------------------------------------------------------------------------------
# task
# ------------------------------------------------------------------------------

task_sdk = KineticSdk::Task.new({
  app_server_url: vars["task"]["server"],
  username: vars["task"]["service_user_username"],
  password: vars["task"]["service_user_password"],
  options: {
    export_directory: "#{task_path}",
  }
})

logger.info "Exporting the task components for the \"#{template_name}\" template."
logger.info "  exporting with api: #{task_sdk.api_url}"

# Export all sources, trees, routines, handlers, groups,
# policy rules, categories, and access keys
task_sdk.export


# ------------------------------------------------------------------------------
# complete
# ------------------------------------------------------------------------------

logger.info "Finished exporting the \"#{template_name}\" template."
