# Action options must be passed as a JSON string
#
# Format with example values:
#
# {
#   "bridgehub" => {
#     "api" => "http://localhost:8080/kinetic-bridgehub/app/manage-api/v1",
#     "client_api" => "http://localhost:8080/kinetic-bridgehub/acme/app/api/v1",
#     "server" => "http://localhost:8080/kinetic-bridgehub",
#     "space_slug" => "acme",
#     "bridges" => {
#       "kinetic-core" => {
#         "bridge_path" =>  "http://localhost:8080/kinetic-bridgehub/app/api/v1/bridges/space-slug-core",
#         "slug" =>  "kinetic-core",
#         "service_endpoint_slug" => "bridgehub"
#       }
#     }
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
#         "filestore_path" =>  "http://localhost:8080/kinetic-filehub/filestores/kinetic-core",
#         "slug" =>  "kinetic-core"
#       }
#     }
#   },
#   "task" => {
#     "api" => "http://localhost:8080/kinetic-task/app/api/v1",
#     "api_v2" => "http://localhost:8080/kinetic-task/app/api/v2",
#     "server" => "http://localhost:8080/kinetic-task",
#     "space_slug" => "foo",
#     "username" => "admin",
#     "password" => "admin_password",
#     "service_user_username" => "service_user_username",
#     "service_user_password" => "secret"
#   },
#   "http_options" => {
#     "log_level" => "info",
#     "gateway_retry_limit" => 5,
#     "gateway_retry_delay" => 1.0,
#     "ssl_ca_file" => "/etc/ca.crt",
#     "ssl_verify_mode" => "none"
#   }
# }

require 'logger'
require 'json'

template_name = "platform-template-base"

logger = Logger.new(STDERR)
logger.level = Logger::INFO
logger.formatter = proc do |severity, datetime, progname, msg|
  date_format = datetime.utc.strftime("%Y-%m-%dT%H:%M:%S.%LZ")
  "[#{date_format}] #{severity}: #{msg}\n"
end


raise "Missing JSON argument string passed to template repair script" if ARGV.empty?
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

def configure_space(space, options={})
  core = options["core"]
  # Update the space slug and space name
  space["slug"] = core["space_slug"]
  space["name"] = core["space_name"]
  space
end


# ------------------------------------------------------------------------------
# setup
# ------------------------------------------------------------------------------

logger.info "Installing gems for the \"#{template_name}\" template."
Dir.chdir(platform_template_path) { system("bundle", "install") }

require 'kinetic_sdk'

http_options = (vars["http_options"] || {}).each_with_object({}) do |(k,v),result|
  result[k.to_sym] = v
end

# ------------------------------------------------------------------------------
# core
# ------------------------------------------------------------------------------

space_config = JSON.parse(File.read("#{core_path}/space.json"))
space = configure_space(space_config, vars)

space_sdk = KineticSdk::Core.new({
  space_server_url: vars["core"]["server"],
  space_slug: space["slug"],
  username: vars["core"]["username"],
  password: vars["core"]["password"],
  options: http_options.merge({ export_directory: "#{core_path}" })
})

logger.info "Repairing the core components for the \"#{template_name}\" template."
logger.info "  repairing with api: #{space_sdk.api_url}"


# ------------------------------------------------------------------------------
# task
# ------------------------------------------------------------------------------

task_sdk = KineticSdk::Task.new({
  app_server_url: vars["task"]["server"],
  username: vars["task"]["username"],
  password: vars["task"]["password"],
  options: http_options.merge({ export_directory: "#{task_path}" })
})

logger.info "Repairing the task components for the \"#{template_name}\" template."
logger.info "  repairing with api: #{task_sdk.api_url}"


# ------------------------------------------------------------------------------
# complete
# ------------------------------------------------------------------------------

logger.info "Finished repairing the \"#{template_name}\" template."
