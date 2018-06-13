# frozen_string_literal: true

require 'uri'

uri = URI.parse(ENV['DATABASE_URL'])

require 'sequel'
require 'logger'

DB = Sequel.connect(ENV['DATABASE_URL'], max_connections: 16)
DB.loggers << Logger.new($stdout) if ENV['SEQUEL_DEBUG'] and ENV['SEQUEL_DEBUG'] == 'true'
DB.extension :pg_array
Sequel.extension :pg_array_ops

#Sequel::Model.plugin :association_pks
#Sequel::Model.plugin :blacklist_security
#Sequel::Model.plugin :instance_hooks
##Sequel::Model.plugin :json_serializer
# Sequel::Model.plugin :polymorphic
# Sequel::Model.plugin :tactical_eager_loading
# Sequel::Model.plugin :validation_helpers
# Sequel::Model.plugin :whitelist_security
# Sequel::Model.plugin :update_or_create
