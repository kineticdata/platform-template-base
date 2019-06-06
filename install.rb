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
#   "core" => {
#     "api" => "http://localhost:8080/kinetic/app/api/v1",
#     "server" => "http://localhost:8080/kinetic",
#     "space_slug" => "foo",
#     "space_name" => "Foo",
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


raise "Missing JSON argument string passed to template install script" if ARGV.empty?
begin
  vars = JSON.parse(ARGV[0])
rescue => e
  raise "Template #{template_name} install error: #{e.inspect}"
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


# ------------------------------------------------------------------------------
# core
# ------------------------------------------------------------------------------

space_config = JSON.parse(File.read("#{core_path}/space.json"))
space = configure_space(space_config, vars)

space_sdk = KineticSdk::Core.new({
  space_server_url: vars["core"]["server"],
  space_slug: space["slug"],
  username: vars["core"]["username"],
  password: vars["core"]["password"]
})

logger.info "Installing the core components for the \"#{template_name}\" template."
logger.info "  installing with api: #{space_sdk.api_url}"


# ------------------------------------------------------------------------------
# task
# ------------------------------------------------------------------------------

task_sdk = KineticSdk::Task.new({
  app_server_url: vars["task"]["server"],
  username: vars["task"]["username"],
  password: vars["task"]["password"]
})

logger.info "Installing the task components for the \"#{template_name}\" template."
logger.info "  installing with api: #{task_sdk.api_url}"

# handlers
Dir["#{task_path}/handlers/*.zip"].each do |handler|
  handler_file = File.new(handler, "rb")
  handler_definition_id = File.basename(handler_file, ".zip")
  
  logger.info "Importing handler #{handler_file.path}"
  task_sdk.import_handler(handler_file, true)

  if handler_definition_id.start_with?("kinetic_core_api_v1")
    logger.info "Updating handler #{handler_definition_id}"
    task_sdk.update_handler(handler_definition_id, {
      "properties" => {
        "api_location" => space_sdk.api_url,
        "api_username" => vars["core"]["service_user_username"],
        "api_password" => vars["core"]["service_user_password"]
      }
    })
  elsif handler_definition_id.start_with?("kinetic_discussions_api_v1")
    logger.info "Updating handler #{handler_definition_id}"
    task_sdk.update_handler(handler_definition_id, {
      "properties" => {
        "api_oauth_location" => "#{space_sdk.server}/app/oauth/token?grant_type=client_credentials&response_type=token",
        "api_location" => "#{space_sdk.server}/app/discussions/api/v1",
        "api_username" => vars["core"]["service_user_username"],
        "api_password" => vars["core"]["service_user_password"]
      }
    })
  elsif handler_definition_id.start_with?("kinetic_task_api_v1")
    logger.info "Updating handler #{handler_definition_id}"
    task_sdk.update_handler(handler_definition_id, {
      "properties" => {
        "api_location" => task_sdk.api_v1_url,
        "api_username" => vars["task"]["service_user_username"],
        "api_password" => vars["task"]["service_user_password"],
        "api_access_key_identifier" => "foo",
        "api_access_key_secret" => "bar"
      }
    })
  elsif handler_definition_id.start_with?("kinetic_task_api_v2")
    logger.info "Updating handler #{handler_definition_id}"
    task_sdk.update_handler(handler_definition_id, {
      "properties" => {
        "api_location" => task_sdk.api_url,
        "api_username" => vars["task"]["service_user_username"],
        "api_password" => vars["task"]["service_user_password"]
      }
    })
    # there are likely more handlers that need to be configured
  end

end


# ------------------------------------------------------------------------------
# complete
# ------------------------------------------------------------------------------

logger.info "Finished installing the \"#{template_name}\" template."
