module Graphoid
  module Types

    LIST = {}
    ENUMS = {}

    class << self
      def generate(model)
        Graphoid::Types::Meta ||= GraphQL::ObjectType.define do
          name("Meta")
          description("Meta Type")
          field("count", types.Int)
        end

        LIST[model] ||= GraphQL::ObjectType.define do
          name = Utils.graphqlize(model.name)
          name("#{name}Type")
          description("Generated model type for #{name}")

          Attribute.fields_of(model).each do |_field|
            type = Graphoid::Mapper.convert(_field)
            name = Utils.camelize(_field.name)
            field(name, type)

            model.class_eval do
              if _field.name.include?('_')
                define_method :"#{Utils.camelize(_field.name)}" do
                  method_name = _field.name.to_s
                  self[method_name] || self.send(method_name)
                end
              end
            end
          end

          Relation.relations_of(model).each do |name, relation|
            relation_class = relation.class_name.safe_constantize

            message = "in model #{model.name}: skipping relation #{relation.class_name}"
            unless relation_class
              STDERR.puts "Graphoid: warning: #{message} because the model name is not valid" if ENV['DEBUG']
              next
            end

            relation_type = LIST[relation_class]
            unless relation_type
              STDERR.puts "Graphoid: warning: #{message} because it was not found as a model" if ENV['DEBUG']
              next
            end

            name = Utils.camelize(relation.name)

            model.class_eval do
              if relation.name.to_s.include?('_')
                define_method :"#{name}" do
                  self.send(relation.name)
                end
              end
            end

            if relation_type
              filter = Graphoid::Filters::LIST[relation_class]
              order  = Graphoid::Orders::LIST[relation_class]

              if Relation.new(relation).many?
                plural_name = name.pluralize

                field plural_name, types[relation_type] do
                  Graphoid::Argument.query_many(self, filter, order)
                  Graphoid::Types.resolve_many(self, relation_class, relation)
                end

                field "_#{plural_name}_meta", Graphoid::Types::Meta do
                  Graphoid::Argument.query_many(self, filter, order)
                  Graphoid::Types.resolve_many(self, relation_class, relation)
                end
              else
                field name, relation_type do
                  argument :where, filter
                  Graphoid::Types.resolve_one(self, relation_class, relation)
                end
              end
            end
          end
        end
      end

      def resolve_one(field, model, association)
        field.resolve -> (obj, args, ctx) do
          filter = args["where"].to_h
          result = obj.send(association.name)
          result = Graphoid::Queries::Processor.execute(model.where({ id: result.id }), filter).first if filter.present? && result
          result
        end
      end

      def resolve_many(field, model, association)
        field.resolve -> (obj, args, ctx) do
          filter = args["where"].to_h
          order = args["order"].to_h
          limit = args["limit"]
          skip = args["skip"]

          result = obj.send(association.name)
          result = Graphoid::Queries::Processor.execute(result, filter) if filter.present?

          if order.present?
            order = Graphoid::Queries::Processor.parse_order(obj.send(association.name), order)
            result = result.order(order)
          end

          result = result.limit(limit) if limit.present?
          result = result.skip(skip) if skip.present?

          result
        end
      end
    end
  end
end