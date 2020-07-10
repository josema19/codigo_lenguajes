class PatternsController < ApplicationController
    include Swagger::Blocks
    skip_before_action :restrict_access, only: [:create, :update]
  
    swagger_path '/v2/patterns/{group}' do
      operation :post do
        key :operationId, 'patterns|create'
        key :tags, ['patterns']
        key :summary, 'Crea información sobre un conjunto de patrones de etiquetas'\
        'asociados a un grupo dado.'
        parameter do
          key :name, 'X-COIN'
          key :in, :header
          key :type, :string
          key :description, 'Token de sesión.'
          key :required, true
        end          
        parameter do
          key :name, :group
          key :in, :path
          key :type, :string
          key :description, 'UUID del grupo.'
          key :required, true
        end      
        parameter do
          key :name, :patterns
          key :in, :patterns
          key :type, :array
          key :description, 'Lista de patrones de etiquetas que deben ser creadas.'
          key :required, true
          items do
            key :title, :pattern
            key :required, [:name, :base_vpc, :base_standard_deviation, :base_data_quality,
              :deficient_vpc, :optimum_vpc, :products_tags, :local]
            property :name do
              key :type, :string
              key :description, 'Nombre asociado a la etiqueta patrón.'
              key :required, true
            end
            property :base_vpc do
              key :type, :string
              key :description, 'Vpc base de la etiqueta patrón.'
              key :required, true
            end
            property :base_standard_deviation do
              key :type, :string
              key :description, 'Desviación estándar base de la etiqueta patrón.'
              key :required, true
            end
            property :base_data_quality do
              key :type, :string
              key :description, 'Información sobre la calidad de datos base del patrón.'
              key :required, true
            end
            property :deficient_vpc do
              key :type, :string
              key :description, 'Vpc deficiente de la etiqueta patrón.'
              key :required, true
            end
            property :optimum_vpc do
              key :type, :string
              key :description, 'Vpc óptima de la etiqueta patrón.'
              key :required, true
            end
            property :products_tags do
              key :type, :array
              key :description, 'Lista de etiquetas de productos asociadas a la'\
              'etiqueta patrón que se quiere crear.'
              items do
                key :title, :products_tag
                key :required, [:name, :image, :base_presence, :base_ratio]
                property :name do
                  key :type, :string
                  key :description, 'Nombre asociado a la etiqueta de producto.'
                  key :required, true
                end
                property :image do
                  key :type, :string
                  key :description, 'URL correspondiente a la imagen de la etiqueta'\
                  'de producto.'
                  key :required, false
                end
                property :base_presence do
                  key :type, :string
                  key :enum, ['0..1']
                  key :description, 'Presencia base de la etiqueta de producto.'
                  key :required, true
                end
                property :base_ratio do
                  key :type, :string
                  key :description, 'Radio base de la etiqueta de producto.'
                  key :required, true
                end
              end
            end
            property :local do
              key :type, :string
              key :description, 'Identificador del local.'
              key :required, true
            end
          end
        end
        response 201 do
          key :description, 'Caso de éxito.'
        end
      end
    end
  
    # Crea un conjunto de patrones de etiquetas para un grupo dado junto con su
    # lote de categorías correspondiente.
    #
    # Parámetros del Método:
    # => group -- String : Identificador del grupo.
    #
    # => name -- String : Nombre del patrón que se va a crear.
    #
    # => base_vpc -- Float : Valor de la venta por comensal base que va a utilizar 
    # la etiqueta patrón.
    #
    # => base_standard_deviation -- Float : Valor base de la desviación estándar
    # de la etiqueta patrón.
    #
    # => base_data_quality -- Float : Valor de la calidad de datos base del patrón.
    #
    # => deficient_vpc -- Float : Valor de la venta por comensal deficiente que va 
    # a utilizar la etiqueta patrón.
    #
    # => optimum_vpc -- Float : Valor de la venta por comensal óptima que va a 
    # utilizar la etiqueta patrón.
    #
    # => products_tags -- Array : Sus elementos son objetos que hacen alusión a las
    # categorías que se deben definir para el patrón que se quiere crear. Para
    # mayor detalle de los objetos que conforman este arreglo ir al modelo 'pattern'.
    #
    # => local -- String : Identificador de un local.
    #
    # Return: 3 arreglos. El primero con los nombres de los patrones creados, el
    # segundo con los nombres de los patrones rechazados y el tercero con los nombres
    # de las etiquetas de productos que no tienen reglas asociadas.
    #
    # Autor: José Barrientos
    # Modificado por: José Barrientos
    # Fecha de Modificación: 28/01/2020
    def create
      # Obtener parámetros de entrada
      group, patterns, reference_date = params['group'], params['pattern'], params['reference_date']
  
      # Validar información del usuario
      user = User.find_by(access_token: authorization_header)
      check_credentials(user)
  
      # Validar que exista la taxonomía Patron para el grupo dado y obtener su uuid.
      # En caso contrario devolver un mensaje de error
      if (!Taxonomy.where('group' => group, 'name' => 'patron').first.nil?)
        taxonomy_uuid = Taxonomy.where('group' => group, 'name' => 'patron').only(:uuid).first['uuid']
      else
        raise ApplicationController::WrongParameter.new('La taxonomía patron no '\
          'existe para el grupo dado.')
      end
  
      # Definir un objeto de patrones válidos y un objeto de patrones inválidos
      # por nombre de patrón y un objeto de patrones inválidos por etiquetas de productos
      valid_patterns, invalid_name, invalid_products_tags = {}, {}, {}
  
      # Obtener información de los efectos de todas las reglas asociadas al grupo
      # dado
      product_tag_rules_effects = ProductTagRules.where({'group' => group}).only('effects')
  
      # Recorrer la data de entrada e ir almacenando su información de ser posible
      patterns.each do |pattern|
        # Definir variable que va a determinar si el patrón es válido o no y obtener
        # el nombre del local en función de su identificador
        is_valid, local_name = true, Local.names_map([pattern['local']])[pattern['local']]
  
        # Validar que los nombres estén definidos correctamente
        if (Tags.where({'taxonomy' => taxonomy_uuid, 'name' => pattern['name']}).first.nil?)
          # Agregar nombre del patrón al arreglo del objeto correspondiente y pasar 
          # al siguiente elemento
          unless (invalid_name.keys.include?(local_name))
            new_invalid_name = {
              local_name => []
            }
            invalid_name.merge!(new_invalid_name)
          end
          invalid_name[local_name] << pattern['name']
          next
        end
  
        # Validar que todas las etiquetas de productos tengan asociadas al menos
        # una regla de la colección product_tag_rules
        pattern['products_tags'].each do |product_tag|
          # Definir booleano para determinar si el producto tiene asociado al menos
          # una regla
          has_rule = false
  
          # Validar que exista una regla para la etiqueta y en caso contrario agregarla
          # al arreglo del objeto correspondiente y cambiar el valor de la variable 
          # is_valid
          product_tag_rules_effects.each do |ptre|
            ptre['effects'].each do |effect|
              if ((effect['tag'] == product_tag['name']) or
                (effect['tag'].split(',').include?(product_tag['name'])))
                has_rule = true
                break
              end
            end
            break if (has_rule)
          end
          if (!has_rule)
            unless (invalid_products_tags.keys.include?(local_name))
              new_invalid_product_tag = {
                local_name => []
              }
              invalid_products_tags.merge!(new_invalid_product_tag)
            end
            invalid_products_tags[local_name] << product_tag['name']
            is_valid = false
          end
        end
  
        # Verificar que el patrón sea válido y agregarlo a la colección patterns
        if (is_valid)
          # Eliminar cualquier documento asociado al patron de existir en la
          # colección patterns
          found_pattern = Pattern.where({'group' => group, 'local' => pattern['local'],
            'name' => pattern['name']}).first
          if (!found_pattern.nil?)
            found_pattern.remove
          end
  
          # Definir nuevo objeto del patrón
          new_pattern = Pattern.new()
  
          # Almacenar valores correspondientes
          new_pattern.group = group
          new_pattern.name = pattern['name']
          new_pattern.base_vpc = pattern['base_vpc'].to_f
          new_pattern.base_standard_deviation = pattern['base_standard_deviation'].to_f
          new_pattern.base_data_quality = pattern['base_data_quality'].to_f
          new_pattern.deficient_vpc = pattern['deficient_vpc'].to_f
          new_pattern.optimum_vpc = pattern['optimum_vpc'].to_f
          new_pattern.products_tags = pattern['products_tags']
          new_pattern.local = pattern['local']
          new_pattern.reference_date = reference_date
  
          # Guardar información en la BD y agregar el nombre del patrón al arreglo 
          # del objeto de patrones válidos
          new_pattern.save
          unless (valid_patterns.keys.include?(local_name))
            new_valid_item = {
              local_name => []
            }
            valid_patterns.merge!(new_valid_item)
          end
          valid_patterns[local_name] << new_pattern.name
        end
      end
  
      # Devolver respuesta con la información pertinente
      render json: {'valid_patterns' => valid_patterns, 'invalid_name' => invalid_name,
        'invalid_products_tags' => invalid_products_tags}, :status => :ok, :content_type => 'application/json'
    end
  
    swagger_path '/v2/patterns/{group}/load_pattern_image' do
      operation :post do
        key :operationId, 'pattern|load_pattern_image'
        key :tags, ['pattern','load_pattern_image']
        key :summary, 'Carga el url de la imagen para una o varias etiquetas de productos.'
        parameter do
          key :name, 'X-COIN'
          key :in, :header
          key :type, :string
          key :description, 'Token de sesión.'
          key :required, true
        end
        parameter do
          key :name, :group
          key :in, :path
          key :type, :string
          key :description, 'Identificador del grupo.'
          key :required, true
        end
        parameter do
          key :name, :product_tag
          key :type, :string
          key :in, :load_pattern_image
          key :description, 'Etiqueta de producto a la que se le pondrá la imagen.'
        end
        parameter do
          key :name, :image
          key :type, :string
          key :in, :load_pattern_image
          key :description, 'Url de la imagen a cargar.'
        end
        response 201 do
          key :description, 'Caso de éxito.'
        end
      end
    end
    # Carga la imagen para la etiqueta de producto asociada a un conjunto de patrones
    # de un grupo dado.
    #
    # Parámetros del Método:
    # => group -- String : Identificador del grupo.
    #
    # => product_tag -- String : Nombre de la etiqueta de producto.
    #
    # => image -- String : Url de la imagen que se le va a cargar a la etiqueta de
    # producto dada.
    #
    # Return: True para indicar que todo se creó correctamente.
    #
    # Autor: José Barrientos
    # Modificado por:
    # Fecha de Modificación: 19/11/2019
    def load_pattern_image
      # Obtener parámetros de entrada
      group, pattern_image = params['group'], params['load_pattern_image']
  
      # Validar información del usuario
      user = User.find_by(access_token: authorization_header)
      check_credentials(user)
  
      # Validar que exista la taxonomía patron para el grupo dado y obtener su uuid.
      # En caso contrario devolver un mensaje de error
      if (!Taxonomy.where('group' => group, 'name' => 'patron').first.nil?)
        taxonomy_uuid = Taxonomy.where('group' => group, 'name' => 'patron').only(:uuid).first['uuid']
      else
        raise ApplicationController::WrongParameter.new('La taxonomía patron no '\
          'existe para el grupo dado.')
      end
  
      # Agregar imagen a cada una de las etiquetas de productos definidas para los
      # patrones creados en la colección pattern
      update = Pattern.load_pattern_image(group, pattern_image['product_tag'], 
        pattern_image['image'])
  
      # Devolver mensaje en caso de que no sea necesaria la actualización
      if (update.class == String)
        render :json => update, :status => :unprocessable_entity, :content_type => 'application/json'
        return false
      end
  
      # Devolver booleano true como respuesta
      render :nothing => true, :status => :ok, :content_type => 'application/json'
    end
  
    swagger_path '/v2/patterns/generate_pdf' do
      operation :get do
        key :operationId, 'pattern|generate_pdf'
        key :tags, ['pattern','generate_pdf']
        key :summary, 'Genera un pdf con la información de todos los patrones que'\
        'tengan metas definidas para un local dado.'
        parameter do
          key :name, 'X-COIN'
          key :in, :query
          key :type, :string
          key :description, 'Token de sesión.'
          key :required, true
        end
        parameter do
          key :name, :local
          key :in, :query
          key :type, :string
          key :description, 'Identificador del local.'
          key :required, true
        end
        parameter do
          key :name, :reference_date
          key :in, :query
          key :type, :string
          key :description, 'Fecha de referencia para hacer los cálculos de la semana.'
        end
        response 201 do
          key :description, 'Caso de éxito.'
        end
      end
    end
    # Genera un archivo PDF vía backend con la información de los patrones asociados
    # a un local y que contengan metas definidas.
    #
    # Parámetros del Método:
    # => local -- String : Identificador de un local.
    #
    # => reference_date -- Date : Fecha de referencia para obtener la fecha de inicio
    # y fin de la semana en la que se encuentra incluída.
    #
    # Return: Archivo PDF con toda la información referente a los patrones.
    #
    # Autor: José Barrientos
    # Modificado por: José Barrientos
    # Fecha de Modificación: 19/12/2019
    def generate_pdf
      # Obtener parámetros de entrada
      local, reference_date = params['local'], to_absolute(DateTime.parse(params['reference_date']))
  
      # Validar información del usuario
      user = User.find_by(access_token: authorization_header)
      check_credentials(user)
      
      # Validar que el local pertenezca a un grupo válido y obtener su uuid
      if (!Group.group(local).nil?)
        group_uuid, group_exclude_taxes = Group.group(local)['uuid'], Group.group(local)['exclude_taxes'] 
      else
        raise ApplicationController::WrongParameter.new('No existe un grupo asociado '\
          'para el local dado.')
      end
  
      # Validar que exista la taxonomía patron y obtener su uuid
      if (!Taxonomy.where('group' => group_uuid, 'name' => 'patron').first.nil?)
        taxonomy_pattern_uuid = Taxonomy.where('group' => group_uuid, 'name' => 'patron').only(:uuid).first['uuid']
      else
        raise ApplicationController::WrongParameter.new('La taxonomía patron no '\
          'existe para el grupo dado.')
      end
  
      # Validar que exista la taxonomía mesonero para el grupo dado y obtener su uuid.
      # En caso contrario devolver un mensaje de error
      if (!Taxonomy.where('group' => group_uuid, 'name' => 'mesonero').first.nil?)
        taxonomy_waiter_uuid = Taxonomy.where('group' => group_uuid, 'name' => 'mesonero').only(:uuid).first['uuid']
      else
        raise ApplicationController::WrongParameter.new('La taxonomía mesonero no '\
          'existe para el grupo dado.')
      end
  
      # Validar que exista la taxonomía No trabajable para el grupo dado y obtener
      # su uuid. En caso contrario se asume que todas las facturas son trabajables
      if (!Taxonomy.where('group' => group_uuid, 'name' => 'No trabajable').first.nil?)
        taxonomy_not_workable_uuid = Taxonomy.where('group' => group_uuid, 'name' => 'No trabajable').only(:uuid).first['uuid']
      end
  
      # Validar que existan patrones creados para el grupo en la colección patterns
      # y obtener todas las entradas posibles
      if (!Pattern.where({'group' => group_uuid}).first.nil?)
        all_patterns_entries_hash = {}
        Pattern.where({'group' => group_uuid, 'local' => local}).all.entries.each do |pattern|
          # Eliminar _id de los atributos
          pattern.attributes.delete_if {|key,value| (key == '_id')}
  
          # Agregar los atributos de pattern al objeto definido anteriormente cuya
          # clave será el nombre del patrón
          all_patterns_entries_hash.merge!({pattern['name'] => pattern.attributes})
        end
      else
        raise ApplicationController::WrongParameter.new('No existen patrones definidos '\
          'en la colección patterns para el grupo del local dado.')
      end
  
      # Validar que exista al menos una regla abierta de tipo Patron definida para
      # el grupo y para la fecha de referencia dada
      if (!Goal.where({'group' => group_uuid, 'local' => local, 'type' => 'PATRON',
        'status' => 'ABIERTA', :open_date.lte => reference_date, :close_date.gte => reference_date}).first.nil?)
        all_goals_entries_hash = {}
        Goal.where({'group' => group_uuid, 'local' => local, 'type' => 'PATRON', 
          'status' => 'ABIERTA', :open_date.lte => reference_date, :close_date.gte => reference_date}).all.entries.each do |goal|
          # Crear nueva estructura con los elementos necesarios
          new_goal = {
            goal['tag_name'] => {
              'indicator' => goal['indicator'],
              'value_indicator' => goal['value_indicator'],
              'goal_products_tags' => goal['categories_metaproducts'],
              'tag' => goal['tag'],
              'tag_name' => goal['tag_name']
            }
          }
  
          # Agregar los atributos de la meta al arreglo declarado anteriormente
          all_goals_entries_hash.merge!(new_goal)
        end
      else
        raise ApplicationController::WrongParameter.new('No existen reglas de tipo '\
          'patron definidas para el grupo, el local y la fecha dada.')
      end
  
      # Definir un arreglo que contendrá la información de los patrones que se van 
      # a mostrar y una estructura highchart
      @patterns_pdf_params, hc = [],  HighchartsFactory.new()
  
      # Obtener etiquetas de exclusión para el local actual
      filters = Tags.get_filters_uuid_for_local(local)
  
      # Obtener etiquetas de exclusión asociadas a la taxonomía No trabajable
      not_workable_filters = !taxonomy_not_workable_uuid.nil? ? (filters & Taxonomy.get_members(taxonomy_not_workable_uuid)) : []
  
      # Obtener fecha de inicio y de fin de la semana en función de la fecha de
      # referencia dada
      begin_week_date, end_week_date = reference_date.beginning_of_week(), reference_date.end_of_week()
  
      # Definir un objeto con información general de todos los patrones
      patterns_general_hash = {
        'invoices' => 0,
        'client_count' => 0,
        'workable_invoices' => {},
        'not_workable_filters' => not_workable_filters,
        'total' => 0
      }
  
      # Obtener número total de facturas trabajables para la semana que se está
      # evaluando usando las etiquetas de exclusión de la taxonomía No trabajable y
      # segmentadas por el uuid de la taxonomía patron para cada uno de los patrones
      # que existen
      Invoice.get_excluded_total_by_tag([local], begin_week_date, end_week_date, 
        taxonomy_pattern_uuid, false, not_workable_filters, [], 'full', group_exclude_taxes).each do |item|
        patterns_general_hash['workable_invoices'].merge!({item['tag_name'] => item['invoices']})
      end
  
      # Obtener información de las ventas válidas totales segmentadas por el uuid 
      # de la taxonomía patron usando todas las etiquetas de exclusión para la 
      # semana actual y previa
      Invoice.get_excluded_total_by_tag([local], begin_week_date, end_week_date, 
        taxonomy_pattern_uuid, false, filters, [], 'full', group_exclude_taxes).each do |item|
        patterns_general_hash['client_count'] += item['client_count']
        patterns_general_hash['invoices'] += item['invoices']
        patterns_general_hash['total'] += item['total']
      end
  
      # Obtener información de cada patrón que posea una meta definida
      all_goals_entries_hash.keys.each do |pattern_name|
        patterns_result_hash = Pattern.calculate_patterns_pdf_params(local, begin_week_date,
          end_week_date, taxonomy_pattern_uuid, taxonomy_waiter_uuid, filters, group_uuid, 
          group_exclude_taxes, all_patterns_entries_hash[pattern_name], 
          all_goals_entries_hash[pattern_name], patterns_general_hash, hc)
  
        # Agregar la información al arreglo correspondiente si el objeto patterns_result_hash
        # es != {}
        if (patterns_result_hash != {})
          @patterns_pdf_params << patterns_result_hash
        end
      end
  
      # Verificar que el arreglo @patterns_pdf_params no sea vacío y en caso contrario
      # mostrar un mensaje de error
      if (@patterns_pdf_params.empty?)
        raise ApplicationController::WrongParameter.new('No existe información de '\
          'patrones que mostrar para la fecha de referencia dada.')
      end
  
      # Definir estructura del archivo pdf a través de un template y construir el
      # archivo. Además, borrar cualquier indicio de highchart que se haya creado
      body = render_to_string(template: 'reports/_pattern_pdf.html.erb')
      pdf = WickedPdf.new.pdf_from_string(body)    
      hc.clear
  
      # Generar pdf
      send_data pdf.force_encoding('BINARY'), :filename => 'patron.pdf', :type => "application/pdf", :disposition => "attachment"
    end
  
    swagger_path '/v2/patterns/{group}/update_reference_date' do
      operation :patch do
        key :operationId, 'patterns|update_reference_date'
        key :tags, ['patterns']
        key :summary, 'Actualiza la fecha de referencia de un grupo o local de la'\
        'colección patterns.'
        parameter do
          key :name, 'X-COIN'
          key :in, :header
          key :type, :string
          key :description, 'Token de sesión.'
          key :required, true
        end
        parameter do
          key :name, :group
          key :in, :path
          key :type, :string
          key :description, 'Identificador del grupo.'
          key :required, true
        end
        parameter do
          key :name, :local
          key :in, :query
          key :type, :string
          key :description, 'Identificador del local.'
          key :required, true
        end
        parameter do
          key :name, :reference_date
          key :in, :query
          key :type, :string
          key :description, 'Fecha de referencia para hacer los cálculos de la semana.'
        end
        response 201 do
          key :description, 'Caso de éxito.'
        end
      end
    end
    # Actualiza la fecha de referencia de un grupo o local dentro de la colección
    # patterns.
    #
    # Parámetros del Método:
    # => group -- String : Identificador del grupo.
    #  
    # => local -- String : Identificador de un local.
    #
    # => reference_date -- Date : Fecha de referencia para obtener la fecha de inicio
    # y fin de la semana en la que se encuentra incluída.
    #
    # Return: True.
    #
    # Autor: José Barrientos
    # Modificado por: José Barrientos
    # Fecha de Modificación: 19/12/2019
    def update_reference_date
      # Obtener parámetros de entrada
      local, group = params['pattern']['local'], params['group']
      reference_date = to_absolute(DateTime.parse(params['pattern']['reference_date']))
  
      # Validar que existan patrones en función del grupo y en caso de existir del
      # local
      if (!local.nil?)
        patterns_entries = Pattern.where({'group' => group, 'local' => local}).all.entries
      else
        patterns_entries = Pattern.where({'group' => group}).all.entries
      end
  
      # Hacer actualizaciones correspondientes
      if (!patterns_entries.empty?)
        # Definir arreglo que contendrá información de las actualizaciones
        reference_dates_array = []
  
        # Recorrer cada entrada y obtener la información correspondiente
        patterns_entries.each do |pe|
          # Definir estructura
          new_reference_date = {
            update_one: {
              filter: { uuid: pe['uuid'] },
              update: { :'$set' => {
                reference_date: reference_date
              }
              }
            }
          }
          reference_dates_array << new_reference_date
        end
  
        # Actualizar información
        if (!reference_dates_array.empty?)
          Pattern.collection.bulk_write(reference_dates_array)
        end
      else
        raise ApplicationController::WrongParameter.new('No existen patrones definidos '\
          'en la colección patterns para el grupo o el grupo y el local dados.')
      end
  
      # Devolver respuesta vacía
      render :nothing => true, :status => :ok, :content_type => 'application/json'
    end
  end
  