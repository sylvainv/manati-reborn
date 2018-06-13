require 'sinatra'
require 'sinatra/base'
require 'sinatra/json'
require 'sinatra/param'
require 'require_all'
require_rel 'lib'

module Manati
  class Api < Sinatra::Application

    TYPE_MAP = {
      :datetime => DateTime,
      :string => String,
      :integer => Integer,
      :double => Float,
      :numeric => Float,
      :boolean => Boolean
    }

    OPERATORS = {
      :eq => '=',
      :gt => '>',
      :gte => '>=',
      :lt => '<',
      :lte => '=<',
      :neq => '!=',
      :regex => '~',
      :nregex => '!~'
    }

    OPERATOR_LITERAL = {
      :eq => '%{column} = ?',
      :gt => '%{column} > ?' ,
      :gte => '%{column} >= ?',
      :lt => '%{column}< ?',
      :lte => '%{column}=< ?',
      :neq => '%{column}!= ?',
      :all => '? %{sub_operator} ALL (%{column})',
      :any => '? %{sub_operator} ANY (%{column})',
      :regex => '%{column} ~ ?',
      :nregex => '%{column} !~ ?'
    }

    ARRAY_OPERATORS = {
      :all => 'ALL',
      :any => 'ANY'
    }

    before do
      param :_select, Array
      param :_order, Array
    end

    before do
      content_type :json
    end

    DB.tables.each do |table|
      route_name = table.to_s.gsub('_', '-').to_sym

      before "/#{route_name}/?" do
        schema = DB.schema(table.to_sym)

        @current_schema = {}
        schema.each do |column|
          @current_schema[column.first] = column.last

          if column.last[:type].to_s.match(/_array$/)
            param column.first, Array, :transform => Sequel.method(:pg_array)
          else
            param column.first, TYPE_MAP[column.last[:type]] || column.last[:type]
          end
        end
      end

      get "/#{route_name}/?" do
        ## FROM
        dataset = DB[table]

        ## SELECT
        dataset = dataset.select(*params[:_select].map(&:to_sym)) if params[:select]

        ## ORDER BY
        puts params
        if params[:_order]
          # Format: _order=column:order OR _order=column:order
          # E.g. _order=id:desc OR _order=id
          params[:_order].split(',').each do |order_column|
            column, order = order_column.split(':')
            order = :asc if order.nil?
            halt 400, {:message => "Order #{order} does not exist"}.to_json unless %i[asc desc].include? order.to_sym

            dataset = dataset.order_append(Sequel.method(order).call(column.to_sym))
          end
        end

        # Build query parameters
        query_parameters = {}

        # Select all parameters
        # Format: column:operator=value OR column=value
        # E.g. id:eq=1 OR id:gt=2 OR id=1

        params.reject{|k,v| %w[_select, _order captures].include? k}.each_pair do |k,v|
          split = k.split(':')
          case split.count
            when 1 then
              interpolator = {
                column: column = split.first,
                operator: operator = :eq
              }
            when 2 then
              interpolator = {
                column: column = split.first,
                operator: operator = split.last
              }
            when 3 then
              column = split.first
              halt 400, {:message => "Format column:array_operator:operator exist if column is an array"} unless @current_schema[column.to_sym][:type].to_s.match(/_array$/)

              operator = split.last.to_sym
              sub_operator = split[1].to_sym
              interpolator = { column: column }
              halt 400, {:message => "Array operator '#{operator}' does not exist"}.to_json unless (ARRAY_OPERATORS).has_key? operator
              halt 400, {:message => "Sub operator '#{split.last}' does not exist"}.to_json unless (OPERATORS).has_key? sub_operator

              interpolator[:operator] = ARRAY_OPERATORS[operator]
              interpolator[:sub_operator] = OPERATORS[sub_operator]
            else
              halt 400, {:message => "Unrecognized querying pattern"}
          end

          halt 400, {:message => "Operator literal '#{operator}' does not exist"}.to_json unless (OPERATOR_LITERAL).has_key? operator.to_sym
          query_parameters[column.to_sym] = {:literal => OPERATOR_LITERAL[operator.to_sym] % interpolator, :value => v}
        end

        query_parameters.keys.select{|x| DB[table].columns.include? x}.each do |param_key|
          param_data = query_parameters[param_key]

          dataset = dataset.where(Sequel.lit("#{param_data[:literal]}", param_data[:value]))
        end

        dataset.all.to_json
      end

      post "/#{route_name}/?" do
        param table, Hash, required: true

        dataset = DB[route_name]

        ## SELECT
        dataset = dataset.returning(*params[:_select].map(&:to_sym)) if params[:select]
        dataset.insert(param[table]).all.to_json
      end

      post "/#{route_name}/:pk?" do
        param :pk, TYPE_MAP[@current_schema.last[:type]]
        param table, Hash, required: true

        dataset = DB[route_name]

        ## SELECT
        dataset = dataset.returning(*params[:_select].map(&:to_sym)) if params[:select]
        dataset.insert(param[table]).all.to_json
      end
    end
  end
end