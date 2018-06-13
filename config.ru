# frozen_string_literal: true

require_relative './api'

app = Rack::Builder.new do
  map '/' do
    run Manati::Api.new
  end
end

run app

