# Action options must be passed as a JSON string
#
# Format with example values:
# 
# {
#   "bridgehub" => {
#     "api" => "http://localhost:8080/kinetic-bridgehub/app/api/v1",
#     "bridge_slug" => "ce-foo",
#     "server" => "http://localhost:8080/kinetic-bridgehub",
#     "space_slug" => "foo",
#     "username" => "admin",
#     "password" => "admin",
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
#     "filestore_slug" => "ce-foo",
#     "server" => "http://localhost:8080/kinetic-filehub",
#     "space_slug" => "foo",
#     "username" => "admin",
#     "password" => "admin"
#   },
#   "request_ce" => {
#     "api" => "http://localhost:8080/kinetic/app/api/v1",
#     "server" => "http://localhost:8080/kinetic",
#     "space_slug" => "foo",
#     "space_name" => "Foo",
#     "username" => "admin",
#     "password" => "admin",
#     "service_user_username" => "service_user_username",
#     "service_user_password" => "secret"
#   },
#   "task" => {
#     "api" => "http://localhost:8080/kinetic-task/app/api/v1",
#     "api_v2" => "http://localhost:8080/kinetic-task/app/api/v2",
#     "server" => "http://localhost:8080/kinetic-task",
#     "space_slug" => "foo",
#     "username" => "admin",
#     "password" => "admin",
#     "service_user_username" => "service_user_username",
#     "service_user_password" => "secret"
#   }
# }

require 'logger'
require 'json'

template_name = "platform-template-base"

logger = Logger.new(STDERR)
logger.level = Logger::INFO


raise "Missing JSON argument string passed to template repair script" if ARGV.empty?
begin
  vars = JSON.parse(ARGV[0])
rescue => e
  raise "Template #{template_name} repair error: #{e.inspect}"
end


# determine the directory paths
platform_template_path = File.dirname(File.expand_path(__FILE__))
core_path = File.join(platform_template_path, "ce")
task_path = File.join(platform_template_path, "task")


# ------------------------------------------------------------------------------
# methods
# ------------------------------------------------------------------------------

def configure_space(space, options={})
  request_ce = options["request_ce"]
  # Update the space slug and space name
  space["slug"] = request_ce["space_slug"]
  space["name"] = request_ce["space_name"]
  space
end


# ------------------------------------------------------------------------------
# setup
# ------------------------------------------------------------------------------

logger.info "Installing gems for the \"#{template_name}\" template."
Dir.chdir(platform_template_path) { system("bundle", "install") }

require 'kinetic_sdk'


# ------------------------------------------------------------------------------
# request
# ------------------------------------------------------------------------------

space_config = JSON.parse(File.read("#{core_path}/space.json"))
space = configure_space(space_config, vars)

space_sdk = KineticSdk::RequestCe.new({
  space_server_url: vars["request_ce"]["server"],
  space_slug: space["slug"],
  username: vars["request_ce"]["username"],
  password: vars["request_ce"]["password"]
})

logger.info "Repairing the core components for the \"#{template_name}\" template."
logger.info "  repairing with api: #{space_sdk.api_url}"


# ------------------------------------------------------------------------------
# task
# ------------------------------------------------------------------------------

task_sdk = KineticSdk::Task.new({
  app_server_url: vars["task"]["server"],
  username: vars["task"]["username"],
  password: vars["task"]["password"]
})

logger.info "Repairing the task components for the \"#{template_name}\" template."
logger.info "  repairing with api: #{task_sdk.api_url}"


# ------------------------------------------------------------------------------
# complete
# ------------------------------------------------------------------------------

logger.info "Finished repairing the \"#{template_name}\" template."
