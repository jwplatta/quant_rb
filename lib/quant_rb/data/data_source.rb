# frozen_string_literal: true

module QuantRb
  module Data
    # Resolves file paths from QuantRb configuration.
    module DataSource
      def self.options_path
        File.expand_path(File.join(QuantRb.config.data_path, QuantRb.config.options_subpath))
      end

      def self.history_path
        File.expand_path(File.join(QuantRb.config.data_path, QuantRb.config.history_subpath))
      end
    end
  end
end
