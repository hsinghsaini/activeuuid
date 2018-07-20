require 'active_record'
require 'active_support/concern'

if ActiveRecord::VERSION::MAJOR == 4 and ActiveRecord::VERSION::MINOR == 2
  module ActiveRecord
    module Type
      class UUID < Binary # :nodoc:
        def type
          :uuid
        end

        def cast_value(value)
          UUIDTools::UUID.serialize(value)
        end
      end
    end
  end

  module ActiveRecord
    module ConnectionAdapters
      module PostgreSQL
        module OID # :nodoc:
          class Uuid < Type::Value # :nodoc:
            def type_cast_from_user(value)
              UUIDTools::UUID.serialize(value) if value
            end
            alias_method :type_cast_from_database, :type_cast_from_user
          end
        end
      end
    end
  end
end

module ActiveUUID
  module Patches
    module Migrations
      def uuid(*column_names)
        options = column_names.extract_options!
        column_names.each do |name|
          type = ActiveRecord::Base.connection.adapter_name.downcase == 'postgresql' ? 'uuid' : 'binary(16)'
          column(name, "#{type}#{' PRIMARY KEY' if options.delete(:primary_key)}", options)
        end
      end
    end

    module Column
      extend ActiveSupport::Concern

      included do
        def type_cast(value)
          return UUIDTools::UUID.serialize(value) if type == :uuid
          super(value)
        end

        def type_cast_code(var_name)
          if ActiveRecord::VERSION::MAJOR < 4
            return "UUIDTools::UUID.serialize(#{var_name})" if type == :uuid
          end
          super(var_name)
        end

        def simplified_type(field_type)
          return :uuid if field_type == 'binary(16)' || field_type == 'binary(16,0)'
          super(field_type)
        end

        # alias_method_chain :type_cast, :uuid
        # alias_method_chain :type_cast_code, :uuid if ActiveRecord::VERSION::MAJOR < 4
        # alias_method_chain :simplified_type, :uuid
      end
    end

    module MysqlJdbcColumn
      extend ActiveSupport::Concern

      included do
        # This is a really hacky solution, but it's the only way to support the
        # MySql JDBC adapter without breaking backwards compatibility.
        # It would be a lot easier if AR had support for custom defined types.
        #
        # Here's the path of execution:
        # (1) JdbcColumn calls ActiveRecord::ConnectionAdapters::Column super constructor
        # (2) super constructor calls simplified_type from MysqlJdbcColumn, since it's redefined here
        # (3) if it's not a uuid, it calls original_simplified_type from ArJdbc::MySQL::Column module
        # (4)   if there's no match ArJdbc::MySQL::Column calls super (ActiveUUID::Column.simplified_type_with_uuid)
        # (5)     Since it's no a uuid (see step 3), simplified_type_without_uuid is called,
        #         which maps to AR::ConnectionAdapters::Column.simplified_type (which has no super call, so we're good)
        #
        alias_method :original_simplified_type, :simplified_type

        def simplified_type(field_type)
          return :uuid if field_type == 'binary(16)' || field_type == 'binary(16,0)'
          original_simplified_type(field_type)
        end
      end
    end


    module PostgreSQLColumn
      extend ActiveSupport::Concern

      included do
        def type_cast(value)
          if ActiveRecord::VERSION::MAJOR >= 4
            return UUIDTools::UUID.serialize(value) if type == :uuid
          end
          super(value)
        end
        # alias_method_chain :type_cast, :uuid if ActiveRecord::VERSION::MAJOR >= 4

        def simplified_type(field_type)
          return :uuid if field_type == 'uuid'
          super(field_type)
        end

        # alias_method_chain :simplified_type, :pguuid
      end
    end

    module Quoting
      extend ActiveSupport::Concern

      included do
        def quote(value, column = nil)
          value = UUIDTools::UUID.serialize(value) if column && column.type == :uuid
          super(value, column)
        end

        def type_cast(value, column = nil)
          value = UUIDTools::UUID.serialize(value) if column && column.type == :uuid
          super(value, column)
        end

        def native_database_types
          @native_database_types ||= super.merge(uuid: { name: 'binary', limit: 16 })
        end

        # alias_method_chain :quote, :visiting
        # alias_method_chain :type_cast, :visiting
        # alias_method_chain :native_database_types, :uuid
      end
    end

    module PostgreSQLQuoting
      extend ActiveSupport::Concern

      included do
        def quote(value, column = nil)
          value = UUIDTools::UUID.serialize(value) if column && column.type == :uuid
          value = value.to_s if value.is_a? UUIDTools::UUID
          super(value, column)
        end

        def type_cast(value, column = nil, *args)
          value = UUIDTools::UUID.serialize(value) if column && column.type == :uuid
          value = value.to_s if value.is_a? UUIDTools::UUID
          super(value, column, *args)
        end

        def native_database_types
          @native_database_types ||= super.merge(uuid: { name: 'uuid' })
        end

        # alias_method_chain :quote, :visiting
        # alias_method_chain :type_cast, :visiting
        # alias_method_chain :native_database_types, :pguuid
      end
    end

    module AbstractAdapter
      extend ActiveSupport::Concern

      included do
        def initialize_type_map(m)
          super(m)
          register_class_with_limit m, /binary\(16(,0)?\)/i, ::ActiveRecord::Type::UUID
        end

        # alias_method_chain :initialize_type_map, :uuid
      end
    end

    def self.apply!
      ActiveRecord::ConnectionAdapters::Table.send :include, Migrations if defined? ActiveRecord::ConnectionAdapters::Table
      ActiveRecord::ConnectionAdapters::TableDefinition.send :include, Migrations if defined? ActiveRecord::ConnectionAdapters::TableDefinition

      if ActiveRecord::VERSION::MAJOR == 4 and ActiveRecord::VERSION::MINOR == 2
        ActiveRecord::ConnectionAdapters::Mysql2Adapter.send :prepend, AbstractAdapter if defined? ActiveRecord::ConnectionAdapters::Mysql2Adapter
        ActiveRecord::ConnectionAdapters::SQLite3Adapter.send :prepend, AbstractAdapter if defined? ActiveRecord::ConnectionAdapters::SQLite3Adapter
      else
        ActiveRecord::ConnectionAdapters::Column.send :prepend, Column
        ActiveRecord::ConnectionAdapters::PostgreSQLColumn.send :prepend, PostgreSQLColumn if defined? ActiveRecord::ConnectionAdapters::PostgreSQLColumn
      end
      ArJdbc::MySQL::Column.send :include, MysqlJdbcColumn if defined? ArJdbc::MySQL::Column

      ActiveRecord::ConnectionAdapters::MysqlAdapter.send :prepend, Quoting if defined? ActiveRecord::ConnectionAdapters::MysqlAdapter
      ActiveRecord::ConnectionAdapters::Mysql2Adapter.send :prepend, Quoting if defined? ActiveRecord::ConnectionAdapters::Mysql2Adapter
      ActiveRecord::ConnectionAdapters::SQLite3Adapter.send :prepend, Quoting if defined? ActiveRecord::ConnectionAdapters::SQLite3Adapter
      ActiveRecord::ConnectionAdapters::PostgreSQLAdapter.send :prepend, PostgreSQLQuoting if defined? ActiveRecord::ConnectionAdapters::PostgreSQLAdapter
    end
  end
end
