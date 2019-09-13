# Action options must be passed as a JSON string
#
# Format with example values:
#
# {
#   "bridgehub" => {
#     "api" => "http://localhost:8080/kinetic-bridgehub/app/api/v1",
#     "client_api" => "http://localhost:8080/kinetic-bridgehub/acme/app/api/v1",
#     "server" => "http://localhost:8080/kinetic-bridgehub",
#     "space_slug" => "acme",
#     "bridges" => {
#       "kinetic-core" => {
#         "access_key_id" => "key",
#         "access_key_secret" => "secret",
#         "bridge_path" =>  "http://localhost:8080/kinetic-bridgehub/acme/app/api/v1/bridges/kinetic-core",
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
#   },
#   "data" => {
#     "users" => [
#       {
#         "username" => "joe.user"
#       }
#     ],
#     "smtp" => {
#       "server" => "smtp.gmail.com",
#       "port" => "587",
#       "tls" => "true",
#       "username" => "joe.blow@gmail.com",
#       "password" => "test",
#       "from_address" => "wally@kinops.io"
#     }
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


raise "Missing JSON argument string passed to template install script" if ARGV.empty?
begin
  vars = JSON.parse(ARGV[0])
  # initialize the data property unless it already exists
  vars["data"] = {} unless vars.has_key?("data")
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

# task handler info values
smtp = vars["data"]["smtp"] || {}
task_handler_configurations = {
  "smtp_email_send" => {
    "server" => smtp["server"] || "mysmtp.com",
    "port" => (smtp["port"] || "25").to_s,
    "tls" => (smtp["tls"] || "true").to_s,
    "username" => smtp["username"] || "joe.blow",
    "password" => smtp["password"] || "password"
  },
  "kinetic_request_ce_notification_template_send" => {
    "smtp_server" => smtp["server"] || "mysmtp.com",
    "smtp_port" => (smtp["port"] || "25").to_s,
    "smtp_tls" => (smtp["tls"] || "true").to_s,
    "smtp_username" => smtp["username"] || "joe.blow",
    "smtp_password" => smtp["password"] || "password",
    "smtp_from_address" => smtp["from_address"] || "j@j.com",
    "smtp_auth_type" => 'plain',
    "api_server" => vars["core"]["server"],
    "api_username" => vars["core"]["service_user_username"],
    "api_password" => vars["core"]["service_user_password"],
    "space_slug" => nil,
    "enable_debug_logging" => "No"
  }
}

http_options = (vars["http_options"] || {}).each_with_object({}) do |(k,v),result|
  result[k.to_sym] = v
end


# ------------------------------------------------------------------------------
# core
# ------------------------------------------------------------------------------

space_sdk = KineticSdk::Core.new({
  space_server_url: vars["core"]["server"],
  space_slug: vars["core"]["space_slug"],
  username: vars["core"]["service_user_username"],
  password: vars["core"]["service_user_password"],
  options: http_options.merge({ export_directory: "#{core_path}" })
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

# update each bridge model mapping with the corresponding bridgehub service endpoint
space_sdk.find_bridge_models.content['models'].each do |model|
  exported_model = space_sdk.find_bridge_model(model['name'], { "export" => true }).content['model']
  exported_model['mappings'].each do |mapping|
    mapping.delete('bridgeName')
    mapping['bridgeSlug'] = vars["bridgehub"]["bridges"]["kinetic-core"]["slug"]
    mapping['serviceEndpointSlug'] = vars["bridgehub"]["bridges"]["kinetic-core"]["service_endpoint_slug"]
    space_sdk.update_bridge_model_mapping(model['name'], mapping['name'], mapping)
  end
end

# create or update oAuth clients
[ oauth_client_prod_bundle, oauth_client_dev_bundle ].each do |client|
  if space_sdk.find_oauth_client(client['clientId']).status == 404
    space_sdk.add_oauth_client(client)
  else
    space_sdk.update_oauth_client(client['clientId'], client)
  end
end

# create any additional users that were specified
(vars["data"]["users"] || []).each do |user|
  space_sdk.add_user(user)
end

# ------------------------------------------------------------------------------
# task
# ------------------------------------------------------------------------------

task_sdk = KineticSdk::Task.new({
  app_server_url: vars["task"]["server"],
  username: vars["task"]["username"],
  password: vars["task"]["password"],
  options: http_options.merge({ export_directory: "#{task_path}" })
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
      "properties" => task_handler_configurations["kinetic_request_ce_notification_template_send"]
    })
  elsif handler_definition_id.start_with?("smtp_email_send")
    task_sdk.update_handler(handler_definition_id, {
      "properties" => task_handler_configurations["smtp_email_send"]
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
