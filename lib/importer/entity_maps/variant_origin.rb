module Importer
  module EntityMaps
    class VariantOrigin < Base
      def self.tsv_to_entity_properties_map
        {
          'variant_origin' => [:variant_origin, default_processor],
        }
      end

      def self.mapped_entity_class
        ::VariantOrigin
      end
    end
  end
end
