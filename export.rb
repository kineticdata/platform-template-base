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
#         "bridge_path" =>  "http://localhost:8080/kinetic-bridgehub/app/api/v1/bridges/space-slug-core",
#         "slug" =>  "kinetic-core"
#       }
#     },
#     "log_level" => "info"
#   },
#   "core" => {
#     "api" => "http://localhost:8080/kinetic/app/api/v1",
#     "server" => "http://localhost:8080/kinetic",
#     "space_slug" => "foo",
#     "space_name" => "Foo",
#     "service_user_username" => "service_user_username",
#     "service_user_password" => "secret",
#     "log_level" => "info"
#   },
#   "discussions" => {
#     "api" => "http://localhost:8080/app/discussions/api/v1",
#     "server" => "http://localhost:8080/app/discussions",
#     "space_slug" => "foo",
#     "log_level" => "info"
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
#     "log_level" => "info"
#   },
#   "task" => {
#     "api" => "http://localhost:8080/kinetic-task/app/api/v1",
#     "api_v2" => "http://localhost:8080/kinetic-task/app/api/v2",
#     "server" => "http://localhost:8080/kinetic-task",
#     "space_slug" => "foo",
#     "service_user_username" => "service_user_username",
#     "service_user_password" => "secret",
#     "log_level" => "info"
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
# methods
# ------------------------------------------------------------------------------

# Removes discussion id attribute from a given model
def remove_discussion_id_attribute(model)
  if !model.is_a?(Array)
    if model.has_key?("attributes")
      scrubbed = model["attributes"].select do |attribute|
        attribute["name"] != "Discussion Id"
      end
    end
    model["attributes"] = scrubbed
  end
  return model
end

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
    log_level: vars["core"]["log_level"] || "info"
  }
})

# fetch export from core service and write to export directory
logger.info "Exporting the core components for the \"#{template_name}\" template."
logger.info "  exporting with api: #{space_sdk.api_url}"
logger.info "   - exporting configuration data (Kapps,forms, etc)"
space_sdk.export_space

# cleanup properties that should not be committed with export
# bridge keys
Dir["#{core_path}/space/bridges/*.json"].each do |filename|
  bridge = JSON.parse(File.read(filename))
  if bridge.has_key?("key")
    bridge.delete("key")
    File.open(filename, 'w') { |file| file.write(JSON.pretty_generate(bridge)) }
  end
end

# cleanup filestore key
filename = "#{core_path}/space.json"
space = JSON.parse(File.read(filename))
if space.has_key?("filestore") && space["filestore"].has_key?("key")
  space["filestore"].delete("key")
  File.open(filename, 'w') { |file| file.write(JSON.pretty_generate(space)) }
end

# cleanup discussion ids
Dir["#{core_path}/**/*.json"].each do |filename|
  model = remove_discussion_id_attribute(JSON.parse(File.read(filename)))
  File.open(filename, 'w') { |file| file.write(JSON.pretty_generate(model)) }
end

# export submissions
logger.info "  - exporting and writing submission data"
SUBMISSIONS_TO_EXPORT.each do |item|
  is_datastore = item["datastore"] || false
  logger.info "    - #{is_datastore ? 'datastore' : 'kapp'} form #{item['formSlug']}"
  # build directory to write files to
  submission_path = is_datastore ?
    "#{core_path}/space/datastore/forms/#{item['formSlug']}" :
    "#{core_path}/kapps/#{item['kappSlug']}/forms/#{item['formSlug']}"

  # create folder to write submission data to
  FileUtils.mkdir_p(submission_path, :mode => 0700)

  # build params to pass to the retrieve_form_submissions method
  params = {"include" => "values", "limit" => 1000, "direction" => "ASC"}

  # open the submissions file in write mode
  file = File.open("#{submission_path}/submissions.ndjson", 'w');

  # ensure the file is empty
  file.truncate(0)
  response = nil
  begin
    # get submissions
    response = is_datastore ?
      space_sdk.find_all_form_datastore_submissions(item['formSlug'], params).content :
      space_sdk.find_form_submissions(item['kappSlug'], item['formSlug'], params).content
    if response.has_key?("submissions")
      # write each submission on its own line
      (response["submissions"] || []).each do |submission|
        # append each submission (removing the submission unwanted attributes)
        file.puts(JSON.generate(submission.delete_if { |key, value| REMOVE_DATA_PROPERTIES.member?(key)}))
      end
    end
    params['pageToken'] = response['nextPageToken']
    # get next page of submissions if there are more
  end while !response.nil? && !response['nextPageToken'].nil?
  # close the submissions file
  file.close()
end
logger.info "  - submission data export complete"

# ------------------------------------------------------------------------------
# task
# ------------------------------------------------------------------------------
logger.info "Removing files and folders from the existing \"#{template_name}\" template."
FileUtils.rm_rf Dir.glob("#{task_path}/*")

task_sdk = KineticSdk::Task.new({
  app_server_url: vars["task"]["server"],
  username: vars["task"]["service_user_username"],
  password: vars["task"]["service_user_password"],
  options: {
    export_directory: "#{task_path}",
    log_level: vars["task"]["log_level"] || "info",
  }
})

logger.info "Exporting the task components for the \"#{template_name}\" template."
logger.info "  exporting with api: #{task_sdk.api_url}"

# export all sources, trees, routines, handlers,
# groups, policy rules, categories, and access keys
task_sdk.export


# ------------------------------------------------------------------------------
# complete
# ------------------------------------------------------------------------------

logger.info "Finished exporting the \"#{template_name}\" template."
