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
#     "username" => "admin",
#     "password" => "admin_password",
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

# access_key used for core to task service
#   communications (webhooks, source)
core_task_access_key = "kinops-request-ce" # leaving name as is for now

# pre-shared key for core webhooks to task
task_access_keys = {
  core_task_access_key => {
    "identifier" => core_task_access_key,
    "secret" => KineticSdk::Utils::Random.simple,
    "description" => "Core Service Access Key",
  }
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

# task source configurations
task_source_properties = {
  "Kinetic Request CE" => {
    "Space Slug" => nil,
    "Web Server" => vars["core"]["server"],
    "Proxy Username" => vars["core"]["service_user_username"],
    "Proxy Password" => vars["core"]["service_user_password"]
  },
  "Kinetic Discussions" => {
    "Space Slug" => nil,
    "Web Server" => vars["core"]["server"],
    "Proxy Username" => vars["core"]["service_user_username"],
    "Proxy Password" => vars["core"]["service_user_password"]
  }
}

# TODO - task handler info values
task_handler_configurations = {
  "smtp_server" => "mysmtp.com",
  "smtp_port" => "25",
  "smtp_tls" => "true",
  "smtp_username" => "joe.blow",
  "smtp_password" => "password",
  "smtp_from_address" => "j@j.com",
  "smtp_auth_type" => 'plain',
}

# ------------------------------------------------------------------------------
# core
# ------------------------------------------------------------------------------

space_sdk = KineticSdk::Core.new({
  space_server_url: vars["core"]["server"],
  space_slug: vars["core"]["space_slug"],
  username: vars["core"]["service_user_username"],
  password: vars["core"]["service_user_password"],
  options: {
    log_level: vars["core"]["log_level"] || "info",
    export_directory: "#{core_path}",
  }
})

# cleanup any kapps that are precreated with the space (catalog)
(space_sdk.find_kapps.content['kapps'] || []).each do |item|
  space_sdk.delete_kapp(item['slug'])
end

# cleanup any existing spds that are precreated with the space (everyone, etc)
space_sdk.delete_space_security_policy_definitions

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
    "Task Server Scheme" => [URI(vars["task"]["server"]).scheme],
    "Task Server Host" => [URI(vars["task"]["server"]).host],
    "Task Server Space Slug" => [vars["task"]["space_slug"]],
    "Task Server Url" => [vars["task"]["server"]],
    "Web Server Url" => [vars["core"]["server"]]
  },
  "name" => vars["core"]["space_name"],
  "filestore" => {
    "slug" => vars["filehub"]["filestores"]["kinetic-core"]["slug"],
    "filehubUrl" => vars["filehub"]["server"],
    "key" => vars["filehub"]["filestores"]["kinetic-core"]["access_key_id"],
    "secret" => vars["filehub"]["filestores"]["kinetic-core"]["access_key_secret"],
  }
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
          { "name" => "Key", "value" => task_access_keys[core_task_access_key]['identifier'] },
          { "name" => "Secret", "value" => task_access_keys[core_task_access_key]['secret'] }
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
            { "name" => "Key", "value" => task_access_keys[core_task_access_key]['identifier'] },
            { "name" => "Secret", "value" => task_access_keys[core_task_access_key]['secret'] }
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
  username: vars["task"]["username"],
  password: vars["task"]["password"],
  options: {
    export_directory: "#{task_path}",
    log_level: vars["task"]["log_level"] || "info",
  }
})

logger.info "Installing the task components for the \"#{template_name}\" template."
logger.info "  installing with api: #{task_sdk.api_url}"

# cleanup playground data
task_sdk.delete_categories
task_sdk.delete_groups
task_sdk.delete_users
task_sdk.delete_policy_rules

# import access keys
Dir["#{task_path}/access-keys/*.json"].each do|file|
  # parse the access_key file
  required_access_key = JSON.parse(File.read(file))
  # determine if access_key is already installed
  not_installed = task_sdk.find_access_key(required_access_key["identifier"]).status == 404
  # set access key secret
  required_access_key["secret"] = task_access_keys[required_access_key["identifier"]]["secret"] || "SETME"
  # add or update the access key
  not_installed ?
    task_sdk.add_access_key(required_access_key) :
    task_sdk.update_access_key(required_access_key["identifier"], required_access_key)
end

# import data from template and force overwrite where necessary
task_sdk.import_groups
task_sdk.import_handlers(true)
task_sdk.import_policy_rules

# import sources
Dir["#{task_path}/sources/*.json"].each do|file|
  # parse the source file
  required_source = JSON.parse(File.read(file))
  # determine if source is already installed
  not_installed = task_sdk.find_source(required_source["name"]).status == 404
  # set source properties
  required_source["properties"] = task_source_properties[required_source["name"]] || {}
  # add or update the source
  not_installed ? task_sdk.add_source(required_source) : task_sdk.update_source(required_source)
end

task_sdk.import_routines(true)
task_sdk.import_categories

# import trees and force overwrite
task_sdk.import_trees(true)

# configure handler info values
task_sdk.find_handlers.content['handlers'].each do |handler|
  handler_definition_id = handler["definitionId"]

  if handler_definition_id.start_with?("kinetic_core_api_v1")
    logger.info "Updating handler #{handler_definition_id}"
    task_sdk.update_handler(handler_definition_id, {
      "properties" => {
        "api_location" => vars["core"]["api"],
        "api_username" => vars["core"]["service_user_username"],
        "api_password" => vars["core"]["service_user_password"]
      }
    })
  elsif handler_definition_id.start_with?("kinetic_discussions_api_v1")
    logger.info "Updating handler #{handler_definition_id}"
    task_sdk.update_handler(handler_definition_id, {
      "properties" => {
        "api_oauth_location" => "#{vars["core"]["server"]}/app/oauth/token?grant_type=client_credentials&response_type=token",
        "api_location" => vars["discussions"]["api"],
        "api_username" => vars["core"]["service_user_username"],
        "api_password" => vars["core"]["service_user_password"]
      }
    })
  elsif handler_definition_id.start_with?("kinetic_task_api_v1")
    logger.info "Updating handler #{handler_definition_id}"
    task_sdk.update_handler(handler_definition_id, {
      "properties" => {
        "api_location" => vars["task"]["api"],
        "api_username" => vars["task"]["service_user_username"],
        "api_password" => vars["task"]["service_user_password"],
        "api_access_key_identifier" => task_access_keys[core_task_access_key]['identifier'],
        "api_access_key_secret" => task_access_keys[core_task_access_key]['secret']
      }
    })
  elsif handler_definition_id.start_with?("kinetic_task_api_v2")
    logger.info "Updating handler #{handler_definition_id}"
    task_sdk.update_handler(handler_definition_id, {
      "properties" => {
        "api_location" => vars["task"]["api_v2"],
        "api_username" => vars["task"]["service_user_username"],
        "api_password" => vars["task"]["service_user_password"]
      }
    })
  elsif handler_definition_id.start_with?("kinetic_request_ce_notification_template_send_v")
    task_sdk.update_handler(handler_definition_id, {
      "properties" => {
        'smtp_server' => task_handler_configurations["smtp_server"],
        'smtp_port' => task_handler_configurations["smtp_port"],
        'smtp_tls' => task_handler_configurations["smtp_tls"],
        'smtp_username' => task_handler_configurations["smtp_username"],
        'smtp_password' => task_handler_configurations["smtp_password"],
        'smtp_from_address' => task_handler_configurations["smtp_from_address"],
        'smtp_auth_type' => task_handler_configurations["smtp_auth_type"],
        'api_server' => vars["core"]["server"],
        'api_username' => vars["core"]["service_user_username"],
        'api_password' => vars["core"]["service_user_password"],
        'space_slug' => nil,
        'enable_debug_logging' => "No"
      }
    })
  elsif handler_definition_id.start_with?("smtp_email_send")
    task_sdk.update_handler(handler_definition_id, {
      "properties" => {
        "server" => task_handler_configurations["smtp_server"],
        "port" => task_handler_configurations["smtp_port"],
        "tls" => task_handler_configurations["smtp_tls"],
        "username" => task_handler_configurations["smtp_username"],
        "password" => task_handler_configurations["smtp_password"]
      }
    })
  elsif handler_definition_id.start_with?("kinetic_request_ce")
    task_sdk.update_handler(handler_definition_id, {
      "properties" => {
        'api_server' => vars["core"]["server"],
        'api_username' => vars["core"]["service_user_username"],
        'api_password' => vars["core"]["service_user_password"],
        'space_slug' => nil,
      }
    })
  end
end

# ------------------------------------------------------------------------------
# complete
# ------------------------------------------------------------------------------

logger.info "Finished installing the \"#{template_name}\" template."
