# frozen_string_literal: true

require 'active_support'
require 'active_support/core_ext'

module StaticSiteBuilder
  # Main module for the static site builder gem

  # Default WebSocket port for live reload server
  DEFAULT_WS_PORT = 3001

  # Default HTTP port for development server
  DEFAULT_PORT = 3000

  # Default layout name
  DEFAULT_LAYOUT_NAME = 'application'
end

require_relative "static_site_builder/version"
require_relative "static_site_builder/builder"
require_relative "static_site_builder/dev_server"
require_relative "static_site_builder/websocket_server"
require_relative "generator"
