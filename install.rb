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
# setup
# ------------------------------------------------------------------------------

logger.info "Installing gems for the \"#{template_name}\" template."
Dir.chdir(platform_template_path) { system("bundle", "install") }

require 'kinetic_sdk'

# ------------------------------------------------------------------------------
# common
# ------------------------------------------------------------------------------

# pre-shared key for core webhooks to task
task_access_key = {
  "description" => "Kinetic Core",
  "identifier" => "kinetic-core",
  "secret" => KineticSdk::Utils::Random.simple
}

# oAuth client for production bundle
oauth_client_prod_bundle = {
  "name" => "Kinetic Bundle - #{vars["core"]["space_slug"]}",
  "description" => "oAuth Client for #{vars["core"]["space_slug"]} client-side bundles",
  "clientId" => "kinetic-bundle",
  "clientSecret" => KineticSdk::Utils::Random.simple(16),
  "redirectUri" => "#{vars["core"]["server"]}/#/OAuthCallback"
}

# oAuth client for development bundle
oauth_client_dev_bundle = {
  "name" => "Kinetic Bundle - Dev",
  "description" => "oAuth Client for client-side bundles in development mode",
  "clientId" => "kinetic-bundle-dev",
  "clientSecret" => KineticSdk::Utils::Random.simple(16),
  "redirectUri" => "http://localhost:3000/#/OAuthCallback"
}

# ------------------------------------------------------------------------------
# core
# ------------------------------------------------------------------------------

space_config = JSON.parse(File.read("#{core_path}/space.json"))

space_sdk = KineticSdk::Core.new({
  space_server_url: vars["core"]["server"],
  space_slug: vars["core"]["space_slug"],
  username: vars["core"]["service_user_username"],
  password: vars["core"]["password"],
  options: {
    export_directory: "#{core_path}",
  }
})

logger.info "Installing the core components for the \"#{template_name}\" template."
logger.info "  installing with api: #{space_sdk.api_url}"

# import the space for the template
space_sdk.import_space(vars["core"]["space_slug"])

# update the space properties
#   set required space attributes
#   set space name from vars
#   setup the filehub service
space_sdk.update_space({
  "attributesMap" => {
    "Discussion Id" => [""],
    "Task Server Host" => [URI(vars["task"]["server"]).host],
    "Task Server Space Slug" => [vars["task"]["space_slug"]],
    "Task Server Url" => [vars["task"]["server"]],
    "Web Server Url" => [vars["core"]["server"]]
  },
  "name" => vars["core"]["space_name"],
  # "filestore" => {                          *** THIS IS CURRENTLY IN DATA-MANAGER ***
  #   "slug" => vars["filehub"]["filestores"]["kinetic-core"]["slug"],
  #   "filehubUrl" => vars["filehub"]["server"],
  #   "key" => vars["filehub"]["filestores"]["kinetic-core"]["access_key_id"],
  #   "secret" => vars["filehub"]["filestores"]["kinetic-core"]["access_key_secret"],
  # }
})

# import kapp & datastore submissions
Dir["#{core_path}/**/*.ndjson"].sort.each do |filename|

  is_datastore = filename.include?('/datastore/forms/')
  form_slug = filename.match(/forms\/(.+)\/submissions\.ndjson/)[1]
  kapp_slug = filename.match(/kapps\/(.+)\/forms/)[1] if !is_datastore

  File.readlines(filename).each do |line|
    submission = JSON.parse(line)
    body = {"values" => submission['values']}
    is_datastore ?
      space_sdk.add_datastore_submission(form_slug, body).content :
      space_sdk.add_submission(kapp_slug, form_slug, body).content
  end

end

# update kinetic task webhook endpoints to point to the correct task server
space_sdk.find_webhooks_on_space.content['webhooks'].each do |webhook|
  url = webhook['url']
  # if the webhook contains a kinetic task endpoint
  if url.include?('/kinetic-task/app/api/v1')
    # replace the server/host portion
    apiIndex = url.index('/app/api/v1')
    url = url.sub(url.slice(0..apiIndex-1), vars["task"]["server"])
    # update the webhook
    space_sdk.update_webhook_on_space(webhook['name'], {
      "url" => url,
      # add the signature access key
      "authStrategy" => {
        "type" => "Signature",
        "properties" => [
          { "name" => "Key", "value" => task_access_key['identifier'] },
          { "name" => "Secret", "value" => task_access_key['secret'] }
        ]
      }
    })
  end
end
space_sdk.find_kapps.content['kapps'].each do |kapp|
  space_sdk.find_webhooks_on_kapp(kapp['slug']).content['webhooks'].each do |webhook|
    url = webhook['url']
    # if the webhook contains a kinetic task endpoint
    if url.include?('/kinetic-task/app/api/v1')
      # replace the server/host portion
      apiIndex = url.index('/app/api/v1')
      url = url.sub(url.slice(0..apiIndex-1), vars["task"]["server"])
      # update the webhook
      space_sdk.update_webhook_on_kapp(kapp['slug'], webhook['name'], {
        "url" => url,
        # add the signature access key
        "authStrategy" => {
          "type" => "Signature",
          "properties" => [
            { "name" => "Key", "value" => task_access_key['identifier'] },
            { "name" => "Secret", "value" => task_access_key['secret'] }
          ]
        }
      })
    end
  end
end

# update the core bridge with the cooresponding bridgehub connection info
space_sdk.update_bridge("Kinetic Core", {
  "key" => vars["bridgehub"]["bridges"]["kinetic-core"]["access_key_id"],
  "secret" => vars["bridgehub"]["bridges"]["kinetic-core"]["access_key_secret"],
  "url" => vars["bridgehub"]["bridges"]["kinetic-core"]["bridge_path"]
})

# create or update oAuth clients
[ oauth_client_prod_bundle, oauth_client_dev_bundle ].each do |client|
  if space_sdk.find_oauth_client(client['clientId']).status == 404
    space_sdk.add_oauth_client(client)
  else
    space_sdk.update_oauth_client(client['clientId'], client)
  end
end



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

logger.info "Installing the task components for the \"#{template_name}\" template."
logger.info "  installing with api: #{task_sdk.api_url}"

# import all data from the template and force overwrite
task_sdk.import(true)

# handlers
task_sdk.find_handlers.content['handlers'].each do |handler|
  handler_definition_id = handler["definitionId"]

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
