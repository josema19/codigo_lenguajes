class Pattern
	include Mongoid::Document

	# Identificador para poder referenciar al pattern único.
	field :uuid, type: String

	# Idenfificador del local.
	field :local, type: String	

	# Identificador del grupo.
	field :group, type: String

	# Fecha de referencia para calcular el incremento acumulado del patrón.
	field :reference_date, type: Date

	# Nombre del patrón.
	field :name, type: String

	# VPC base del patrón.
	field :base_vpc, type: Float

	# Desviación estándar base del patrón.
	field :base_standard_deviation, type: Float

	# Calidad de datos base del patrón.
	field :base_data_quality

	# VPC deficiente del patrón.
	field :deficient_vpc, type: Float

	# VPC óptima del patrón.
	field :optimum_vpc, type: Float

	# Arreglo de etiquetas de productos asociadas al patrón actual. Cada uno de
	# sus elementos es un objeto de la forma:
	#
	# => {
	# => 	name: 'String' que representa el nombre de la etiqueta de producto.
	# =>
	# => 	image 'String' que define una url que contiene la ubicación de la
	# => 	imagen que se utilizará para dibujar la etiqueta de producto.
	# =>
	# => 	base_presence 'Float' que representa la presencia base de la etiqueta
	# => 	de producto.
	# =>
	# => 	base_ratio 'Float' que representa el radio base de la etiqueta de producto.
	# => }
	field :products_tags, type: Array

	# Crear índices.
	index({group: 1, local: 1, name: 1}, {unique: true})
	index({local: 1, name: 1}, {unique: true})
	index({uuid: 1}, {unique: true})

	# Función que genera un hash único para el uuid del patrón.
	def self.generate_uuid(seed=nil)
		if (seed)
			return Digest::MD5.hexdigest(seed)
		else
			return SecureRandom.uuid
		end
	end

	# Función que valida que todos los elementos que van a ingresar a la Base de
	# Datos estén definidos correctamente.
	before_create do |pattern|
		# Verificar que el uuid del grupo no sea vacío ni nulo y que además tenga
		# asociado un grupo válido.
		if ((pattern['group'].nil?) or (pattern['group'] == '') or (Group.group_or_subgroup(pattern['group']).nil?))
			raise ApplicationController::WrongParameter.new('El uuid del grupo no puede '\
				'ser vacío ni nulo o no pertenece a ningún grupo conocido.')
		else
			pattern['group'] = pattern['group'].strip
		end

	    # Verificar que el identificador del local no sea vacío y que guarde relación
	    # con el uuid del grupo dado.
	    if ((pattern['local'].nil?) or (pattern['local'] == '') or (Group.subgroup_from_locals(pattern['local']).nil?) or 
	      (Group.subgroup_from_locals(pattern['local'])['uuid'] != pattern['group']))
	      raise ApplicationController::WrongParameter.new('El identificador del local no '\
	        'puede ser vacío ni nulo o no guarda relación con el uuid del grupo dado.')
	    else
	      pattern['local'] = pattern['local'].strip
	    end

		# Verificar que el nombre de la regla no sea vacío ni nulo.
		if ((pattern['name'].nil?) or (pattern['name'] == ''))
			raise ApplicationController::WrongParameter.new('El nombre del patrón no '\
				'puede ser vacío o nulo.')
		else
			pattern['name'] = pattern['name'].strip
		end

		# Verificar que el valor de la venta por comensal base sea un número mayor
		# a cero.
		if (pattern['base_vpc'] <= 0.0)
			raise ApplicationController::WrongParameter.new('El valor de la vpc base '\
				'debe ser un flotante mayor a 0.')
		end

		# Verificar que el valor de la desviación estándar base sea un número mayor
		# a cero.
		if (pattern['base_standard_deviation'] <= 0.0)
			raise ApplicationController::WrongParameter.new('El valor de la desviación '\
				'estandar base debe ser un flotante mayor a 0.')			
		end

		# Verificar que el valor de la venta por comensal deficiente sea un número 
		# mayor a cero.
		if (pattern['deficient_vpc'] <= 0.0)
			raise ApplicationController::WrongParameter.new('El valor de la vpc deficiente '\
				'debe ser un flotante mayor a 0.')
		end

		# Verificar que el valor de la venta por comensal óptim< sea un número mayor
		# a cero.
		if (pattern['optimum_vpc'] <= 0.0)
			raise ApplicationController::WrongParameter.new('El valor de la vpc óptima '\
				'debe ser un flotante mayor a 0.')			
		end

		# Crear el identificador (uuid) para la regla que se va a almacenar.
		seed = pattern['group'] + pattern['local'] + pattern['name']
		pattern['uuid'] = Pattern.generate_uuid(seed) if (pattern['uuid'].nil? or pattern['uuid'] == '')
	end

  # Construye un objeto con información relevante de las etiquetas de productos
  # asociadas a un patrón.
  #
  # Parámetros del Método:
  # => base_products_tags -- Array : Arreglo con la información base de las 
  # etiquetas de productos que provienen de la colección patterns.
  #
  # => all_products_tags -- Array : Arreglo que contiene la información calculada 
  # de las etiquetas de productos que conforman un patrón.
  #
  # => goal -- Hash : Objeto que contiene la información de una meta asociada al
  # patrón actual.
  #
  # => pattern_client_count -- Float : Cantidad de comensales asociados a un patrón.
  #
  # Returns: Objeto con la información relevante de todas las etiquetas de productos
  # que conforman el patrón.
  #
  # Autor: José Barrientos
  # Modificado por: José Barrientos
  # Fecha de Modificación: 17/02/2020
	def self.build_new_products_tags(base_products_tags, all_products_tags, goal, 
		pattern_client_count)
		# Definir objeto general que se va a regresar como respuesta y que va a contener
		# todos las etiquetas de productos asociadas al patrón
		new_products_tags = {}

		# Comenzar a obtener la información necesaria para cada una de las etiquetas
		base_products_tags.each do |bpt|
			# Obtener el índice de la posición del arreglo all_products_tags donde se 
			# encuentra el nombre de la etiqueta base
			index = all_products_tags.index {|item| item['category_name'] == bpt['name']}

			if (!index.nil?)
				# Definir un objeto para la etiqueta actual
				new_product_tag = {bpt['name'] => []}

				# Obtener vpc incremental base
				incremental_base_vpc = bpt['base_presence'] * bpt['base_ratio'] * all_products_tags[index]['average_price']

				# Obtener presencia, radio y vpc incremental de la etiqueta de producto 
				# actual
				calculated_presence = all_products_tags[index]['client_count'] / pattern_client_count
				calculated_ratio = (all_products_tags[index]['client_count'] != 0.0) ?
				(all_products_tags[index]['articles'] / all_products_tags[index]['client_count']) : 0.0
				calculated_incremental_vpc = calculated_presence * calculated_ratio * all_products_tags[index]['average_price']

				# Obtener vpc incremental de la meta cuando sea el caso
				incremental_goal_vpc = (calculated_ratio * goal['value_indicator'] *
				all_products_tags[index]['average_price']) if (goal['goal_products_tags'].include?(bpt['name']))

				# Agregar información de la meta si el nombre de la etiqueta de producto
				# coincide con el que se encuentra en la meta
				if (goal['goal_products_tags'].include?(bpt['name']))
					new_product_tag_goal = {
						'image' => bpt['image'],
						'name' => bpt['name'],
						'presence' => (goal['indicator'] == 'PP') ? goal['value_indicator'] : calculated_presence,
						'ratio' => (goal['indicator'] == 'PR') ? goal['value_indicator'] : calculated_ratio,
						'vpc' => (incremental_goal_vpc - incremental_base_vpc).round(0)
					}
					new_product_tag[bpt['name']] << new_product_tag_goal
				end

				# Agregar información de la meta alcanzada
				new_product_tag_achieved_goal = {
					'image' => !goal['goal_products_tags'].include?(bpt['name']) ? bpt['image'] : '',
					'name' => bpt['name'],
					'presence' => calculated_presence,
					'ratio' => calculated_ratio,
					'vpc' => (calculated_incremental_vpc - incremental_base_vpc).round(0)
				}
				new_product_tag[bpt['name']] << new_product_tag_achieved_goal

				# Agregar patrón al objeto general
				new_products_tags.merge!(new_product_tag)
			end
		end

		# Devolver respuesta
		return new_products_tags
	end

  # Construye un objeto con los parámetros que serán utilizados para crear la hoja
  # del pdf que está asociado a los patrones de consumo para un local.
  #
  # Parámetros del Método:
  # => local -- String : Identificador de un local.
  #
  # => begin_date -- Date : Fecha de inicio desde donde se quiere comenzar a
  # obtener la información.
  #
  # => end_date -- Date : Fecha final hasta donde se quiere obtener la información.
  #
  # => pattern_taxonomy -- String : Uuid de la taxonomía patron.
  #
  # => meser_taxonomy -- String : Uuid de la taxonomía mesero.
  #
  # => filters -- Array : Información que contiene los ids de las etiquetas de 
  # exclusión.
  #
  # => group -- String : Identificador del grupo asociado al local dado.
  #
  # => exclude_taxes -- Boolean : Indica si se excluye o no el impuesto.
  #
  # => pattern -- Hash : Objeto que contiene la información de un patrón proveniente
  # de la colección patterns.
  #
  # => goal -- Hash : Objeto que contiene información relevante de una meta tipo
  # PATRON que ha sido definida en la colección goals.
  #
  # => patterns_general_info -- Hash : Objeto que contiene información general de
  # todos los patrones como el total de las ventas, la cantidad de comensales,
  # la cantidad de facturas y las facturas trabajables de la semana que se está
  # evaluando y la semana previa.
  #
  # => hc -- Highchart : Estructura para crear una gráfica.
  #
  # Returns: Objeto con la información que será plasmada en el pdf asociado a los
  # patrones de consumo.
  #
  # Autor: José Barrientos
  # Modificado por: José Barrientos
  # Fecha de Modificación: 30/01/2020
	def self.calculate_patterns_pdf_params(local, begin_date, end_date, pattern_taxonomy,
		meser_taxonomy, filters, group, exclude_taxes, pattern, goal, patterns_general_info, hc)
    # Definir acción del controlador
    view_command = ActionController::Base.helpers

    # Obtener información de la moneda del local
    current_local = Local.get_locals_info([local])[0]
    @locale = current_local['locale']
    I18n.locale = current_local['locale'] || I18n.default_locale

    # Definir objeto que se devolverá como resultado y un iterador para la lista
    # de meseros
    result_pattern, position_count = {}, 1

    # Obtener información de la etiqueta de inclusión
    include_tags = Taxonomy.get_grouped_tags([goal['tag']])

    # Calcular los valores de la semana actual necesarios para cargar la información 
    # del pdf
    self.get_pdf_pattern_information([local], begin_date, end_date, pattern_taxonomy, 
    	meser_taxonomy, filters, include_tags, exclude_taxes, group, pattern, goal,
    	patterns_general_info, result_pattern)

    # Devolver resultado vació si no se encontró información del patrón
    return result_pattern if (result_pattern.empty?)

    # Agregar campos adicionales al objeto result_pattern
    result_pattern['goal_indicator'] = goal['indicator']
    result_pattern['local_name'] = Local.names_map([local])[local]
    result_pattern['pattern_name'] = goal['tag_name']
    result_pattern['time_window'] = 'SEMANA %s (%s al %s)' % [begin_date.strftime("%V").to_i,
    	view_command.l(begin_date, format: '%d'), view_command.l(end_date, format: '%d de %b.')]
    result_pattern['total_vs_general_total'] = '%s / %s' % [view_command.number_to_currency(result_pattern['total'], :locale => @locale), 
    	view_command.number_to_currency(result_pattern['general_total'], :locale => @locale)]
    result_pattern['invoices_vs_general_invoices'] = '%s/%s' % [result_pattern['invoices'],  result_pattern['general_invoices']]
    result_pattern['client_count_vs_general_client_count'] = '%s/%s' % [result_pattern['client_count'],  result_pattern['general_client_count']]
    result_pattern['next_target'] = 'Esta semana seguiremos trabajando sobre la categoría %s. ' % [goal['goal_products_tags'][0].downcase]    
    result_pattern['next_target'] += 'Si deseas cambiar el objetivo para esta experiencia comunícate con tu ejecutivo de cuenta.'

    # Modificar campos necesarios del objeto result_pattern
    result_pattern['total_per'] = '(' + result_pattern['total_per'].to_s + '%)'
    result_pattern['invoices_per'] = '(' + result_pattern['invoices_per'].to_s + '%)'    
    result_pattern['workable_invoices'] = result_pattern['workable_invoices'].to_s + '%'
    if (goal['indicator'] == 'PP')
    	result_pattern['goal'] = '%s%% de presencia en %s por mesero.' % [result_pattern['goal'], goal['goal_products_tags'][0].downcase]
    	result_pattern['achieved_goal'] = result_pattern['achieved_goal'].to_s + '%' 
    else
    	result_pattern['goal'] = '%s unidades de %s por comensal.' % [result_pattern['goal'], goal['goal_products_tags'][0].downcase]
    end
    result_pattern['best_waiters_vpc'].each do |bwvpc|
    	bwvpc['vpc'] = view_command.number_to_currency(bwvpc['vpc'], :locale => @locale)
    end
    result_pattern['worst_waiters_vpc'].each do |wwvpc|
    	wwvpc['vpc'] = view_command.number_to_currency(wwvpc['vpc'], :locale => @locale)
    end
    result_pattern['waiters_info'].each do |wi|
    	wi['achieved_goal'] = wi['achieved_goal'].to_s + '%' if (goal['indicator'] == 'PP')
    	wi['name'] = position_count.to_s + '. ' + wi['name']
    	wi['total'] = view_command.number_to_currency(wi['total'], :locale => @locale)
    	wi['vpc'] = view_command.number_to_currency(wi['vpc'], :locale => @locale)
    	wi['workable_invoices'] = wi['workable_invoices'].to_s + '%'

    	# Aumentar valor de la posición
    	position_count += 1
    end
    result_pattern['weekly_vpc'] = view_command.number_to_currency(result_pattern['weekly_vpc'], :locale => @locale)
    result_pattern['weekly_increase'] = view_command.number_to_currency(result_pattern['weekly_increase'], :locale => @locale)
    result_pattern['incremental_vpc'] = view_command.number_to_currency(result_pattern['incremental_vpc'], :locale => @locale)
    result_pattern['cumulative_increase'] = view_command.number_to_currency(result_pattern['cumulative_increase'].round(2), :locale => @locale)

    # Crear información de la gráfica
    rest_begin_date_index = -1
    result_pattern['highchart']['dates'].each do |date|
    	if (date == pattern['reference_date'].strftime('%d/%m'))
    		rest_begin_date_index = result_pattern['highchart']['dates'].index(date)
    	end
    end
    result_pattern['highchart']['historical_vpc'][-1] = {'y' => result_pattern['highchart']['historical_vpc'][-1], 'dataLabels' => {'enabled' => true}}
    result_pattern['graphic_image'] = hc.create_lines_pattern(result_pattern['highchart']['dates'], 
    	result_pattern['highchart']['historical_vpc'], result_pattern['highchart']['base_vpc'],
    	result_pattern['highchart']['optimum_vpc'], @locale, rest_begin_date_index, 'line')

    # Devolver respuesta
    return result_pattern
	end

	# Devuelve un objeto que contiene un indicador (-1, 0, 1) y un valor asociado
	# para determinar si en la diferencia entre dos valores hubo pérdida, neutralidad
	# o ganancia.
	#
  # Parámetros del Método:
  # => value_1 -- Float : Primer valor flotante para la función.
  #
  # => Value_2 -- Float : Segundo valor flotante para la función.
  #
  # => is_goal -- Boolean : Indica si se está haciendo la evaluación de la meta
  # asociada a un patrón. Este parámetro es opcional.
  #
  # Returns: Objeto con un indicador y su valor.
  #
  # Autor: José Barrientos
  # Modificado por: José Barrientos
  # Fecha de Modificación: 19/12/2019
	def self.get_indicator_value(value_1, value_2, is_goal=nil)
		# Definir objeto que se va a devolver como respuesta
		new_item_hash = {
			'indicator' => 0,
			'value' => '(0%)'
		}

		# Asignar valores correspondientes al objeto anterior según sea el caso
		if ((!is_goal.nil?) and (is_goal))
			new_item_hash['indicator'] = (value_1 <= value_2) ? 1 : -1
			new_item_hash['value'] = (value_1 <= value_2) ? 'CUMPLIDA' : 'NO CUMPLIDA'				
		else
			new_value = (((value_1 - value_2) * 100) / value_2).round(0).to_s
			new_item_hash['indicator'] = (value_1 < value_2) ? -1 : 1
			new_item_hash['value'] = (value_1 < value_2) ? '(' + new_value + '%)' : '(+' + new_value + '%)' 
		end

		# Regresar respuesta
		return new_item_hash
	end

  # Construye un objeto de valores relevantes para un patron dado.
  #
  # Parámetros del Método:
  # => locals -- Array : Arreglo que continene los identificadores de un conjunto
  # de locales.
  #
  # => begin_date -- Date : Fecha de inicio desde donde se quiere comenzar a
  # obtener la información.
  #
  # => end_date -- Date : Fecha final hasta donde se quiere obtener la información.
  #
  # => pattern_taxonomy -- String : Uuid de la taxonomía patron.
  #
  # => meser_taxonomy -- String : Uuid de la taxonomía mesero.
  #
  # => filters -- Array : Información que contiene los ids de las etiquetas de 
  # exclusión.
  #
  # => include_tags -- Array : Contiene la información sobre las etiquetas de 
  # inclusión que se van a utilizar para obtener las ventas.
  #
  # => exclude_taxes -- Boolean : Indica si se excluye o no el impuesto.
  #
  # => group -- String : Identificador del grupo asociado al local dado.
  #
  # => pattern -- Hash : Objeto que contiene la información de un patrón
  # proveniente de la colección patterns.
  #
  # => goal -- Hash : Objeto que contiene información relevante de una meta tipo
  # PATRON que ha sido definida en la colección goals.
  #
  # => patterns_general_info -- Hash : Objeto que contiene información general
  # de todos los patrones.
  #
  # => pattern_params -- Hash : Objeto vacío que contendrá toda la información
  # que será mostrada en el PDF.
  #
  # Returns: Objeto con la información que será plasmada en el pdf asociado a los
  # patrones de consumo.
  #
  # Autor: José Barrientos
  # Modificado por: José Barrientos
  # Fecha de Modificación: 17/02/2020
	def self.get_pdf_pattern_information(locals, begin_date, end_date, pattern_taxonomy,
		meser_taxonomy, filters, include_tags, exclude_taxes, group, pattern, goal, 
		patterns_general_info, pattern_params)
		# Obtener información de las ventas del patrón segmentadas por su uuid y por
		# las etiquetas de productos para la semana que se está evaluando
		sales_prods_tags_pattern_hash = WaiterGoal.get_general_waiter_information(locals,
			begin_date, end_date, pattern_taxonomy, false, filters, include_tags, 
			'full', exclude_taxes, goal['tag'], 'product-experience-tags', group, 'sales,categories')

		# Separar la información de las ventas y de las etiquetas de productos
		sales_pattern_hash, products_tags_pattern_array = 
		sales_prods_tags_pattern_hash['sales'][0], sales_prods_tags_pattern_hash['categories']

		# Regresar objeto vacío si no hay información
		return pattern_params if ((sales_pattern_hash.nil?) and (products_tags_pattern_array.empty?))

		# Obtener índice de la etiqueta de producto que está relacionada con la 
		# meta de la etiqueta de producto
		index = pattern['products_tags'].index {|item| item['name'] == goal['goal_products_tags'][0]}

		# Agregar información del radio y la presencia para el objeto sales_pattern_hash
		sales_pattern_hash['ratio'] = (sales_pattern_hash['articles'] / sales_pattern_hash['client_count'].to_f)
		sales_pattern_hash['presence'] = (sales_pattern_hash['client_count'] / patterns_general_info['client_count'].to_f)

		# Obtener información de la calidad de datos del patrón
		workable_invoices = (sales_pattern_hash['invoices'] /
			(!patterns_general_info['workable_invoices'][pattern['name']].nil? ?
				patterns_general_info['workable_invoices'][pattern['name']].to_f : 1))

		# Verificar que la categoría definida en la meta se encuentre dentro del
		# arreglo products_tags_pattern_array y en caso contrario agregarla con 
		# todos sus valores en cero.
		# NOTA_1: Puede suceder que la categoría de la meta no se haya vendido.
		index_cat = products_tags_pattern_array.index {|item| item['category_name'] == goal['goal_products_tags'][0]}
		if (index_cat.nil?)
			new_item = {
				'subtotal' => 0.0,
				'tax' => 0.0,
				'discount' => 0.0,
				'invoices' => 0,
				'articles' => 0,
				'client_count' => 0,
				'tag_id' => products_tags_pattern_array[0]['tag_id'],
				'tag_name' => products_tags_pattern_array[0]['tag_name'],
				'category_branch' => goal['goal_products_tags'],
				'total' => 0,
				'average_price' => 0.0,
				'category_name' => goal['goal_products_tags'][0]
			}
			products_tags_pattern_array << new_item
		end

		# Obtener un objeto con la información de todas las categorías que conforman
		# el patrón para la semana que se está evaluando		
		current_products_tags_hash = self.build_new_products_tags(pattern['products_tags'],
			products_tags_pattern_array, goal, sales_pattern_hash['client_count'])

		# Obtener información de la meta para la semana actual y descartarla del 
		# arreglo current_products_tags_hash
		current_product_tag_array = current_products_tags_hash[goal['goal_products_tags'][0]]
		current_products_tags_hash.delete_if {|key,value| key == goal['goal_products_tags'][0]}

		# Llenar parte del objeto que se devolverá como respuesta
		pattern_params['total'] = sales_pattern_hash['total'].round(2)
		pattern_params['general_total'] = patterns_general_info['total'].round(2)
		pattern_params['total_per'] = ((pattern_params['total'] * 100) / pattern_params['general_total']).round(0)
		pattern_params['invoices'] = sales_pattern_hash['invoices']
		pattern_params['general_invoices'] = patterns_general_info['invoices']
		pattern_params['invoices_per'] = ((pattern_params['invoices'] * 100) / pattern_params['general_invoices']).round(0)
		pattern_params['client_count'] = sales_pattern_hash['client_count']
		pattern_params['general_client_count'] = patterns_general_info['client_count']
		pattern_params['workable_invoices'] = (workable_invoices * 100).round(0)
		pattern_params['workable_invoices_per'] = self.get_indicator_value(workable_invoices, pattern['base_data_quality'])
		pattern_params['goal'] = ((goal['indicator'] == 'PP') ? (current_product_tag_array[0]['presence'] * 100).round(0) : (current_product_tag_array[0]['ratio']).round(1))
		pattern_params['achieved_goal'] = ((goal['indicator'] == 'PP') ? (current_product_tag_array[1]['presence'] * 100).round(0) : (current_product_tag_array[1]['ratio']).round(1))
		pattern_params['achieved_goal_per'] = ((goal['indicator'] == 'PP') ? self.get_indicator_value(current_product_tag_array[1]['presence'],
			pattern['products_tags'][index]['base_presence']) : self.get_indicator_value(current_product_tag_array[1]['ratio'], pattern['products_tags'][index]['base_ratio']))
		pattern_params['achieved_goal_vpc'] = current_product_tag_array[1]['vpc']
		pattern_params['achieved_goal_info'] = self.get_indicator_value(pattern_params['goal'], pattern_params['achieved_goal'], true)

		# Obtener información de las facturas trabajables de los meseros segmentadas
		# por la etiqueta del patrón actual
		workable_info_waiters_array = WaiterGoal.get_general_waiter_information(locals,
			begin_date, end_date, meser_taxonomy, false, patterns_general_info['not_workable_filters'],
			include_tags, 'full', exclude_taxes, goal['tag'], 'product-experience-tags',
			group, 'sales')['sales']

		# Obtener información de las ventas de los meseros segmentadas por la etiqueta
		# del patrón actual y por las etiquetas de productos para la semana que se está evaluando
		sales_prods_tags_waiters_hash = WaiterGoal.get_general_waiter_information(locals,
			begin_date, end_date, meser_taxonomy, false, filters, include_tags, 'full', 
			exclude_taxes, goal['tag'], 'product-experience-tags', group, 'sales,categories')

		# Separar la información de las ventas y de las etiquetas de productos
		sales_waiters_array, products_tags_waiters_array = 
		sales_prods_tags_waiters_hash['sales'], sales_prods_tags_waiters_hash['categories']

		# Ordenar arreglo sales_waiters_array en función de su vpc y eleminiar del 
		# arreglo sales_prods_tags_waiters_hash las categorías innecesarias
		sales_waiters_array.sort_by! {|item| -item['total_per_client']}
		products_tags_waiters_array.delete_if {|item| item['category_branch'] != goal['goal_products_tags']}

		# Definir cuatro arreglos para guardar la información de los meseros relevantes
		# (con alta vpc y presencia) y de los meseros menos relevantes (con baja vpc
		# y presencia)
		best_waiters_vpc, best_waiters_presence, worst_waiters_vpc, worst_waiters_presence = [], [], [], []

		# Definir un contador para tener la cantidad de meseros que alcanzaron la meta
		# y un arreglo que va a contener la información de todos los meseros que están
		# relacionados con el patrón
		achieved_goal_waiters_count, waiters_info_array = 0, []

		# Agregar información relevante asociada a los meseros que participaron en
		# el patrón actual
		sales_waiters_array.each do |swa|
			# Obtener información de las facturas trabajables del mesero actual
			index = workable_info_waiters_array.index {|wiwa| wiwa['tag_id'] == swa['tag_id']}
			workable_invoices = !index.nil? ? workable_info_waiters_array[index]['invoices'] : swa['invoices']

			# Definir estructura con parte de la información del mesero y agregarla al 
			# arreglo correspondiente
			new_waiter_info = {
				'achieved_goal' => 0,
				'client_count' => swa['client_count'].round(0),
				'goal' => nil,
				'name' => swa['tag_name'].strip.downcase.titleize.split(' ').join(' '),
				'total' => swa['total'].round(2),
				'vpc' => swa['total_per_client'].round(2),
				'uuid' => swa['tag_id'],
				'workable_invoices' => (!workable_invoices.nil? ? ((swa['invoices'] * 100) / workable_invoices.to_f).round(0) : 100)
			}
			waiters_info_array << new_waiter_info
		end

		# Agregar información de la pesencia y el radio en el arreglo products_tags_waiters_array,
		# contar el número de meseros que lograron la meta, agregar información restante de
		# cada mesero a la lista correspondiente
		products_tags_waiters_array.each do |ptwa|
			# Obtener índice donde se encuentra almacenada la información general
			# del mesero para obtener la información de las facturas válidas
			index = sales_waiters_array.index {|swa| swa['tag_id'] == ptwa['tag_id']}
			waiter_all_clients = !index.nil? ? sales_waiters_array[index]['client_count'].to_f : 1.0

			# Definir nuevos campos
			ptwa['presence'] = ptwa['client_count'] / waiter_all_clients
			ptwa['ratio'] = ptwa['articles'] / ptwa['client_count'].to_f

			# Contar el número de meseros que lograron la meta y definir un string 
			# para calificar si se logró o no la meta
			if (goal['indicator'] == 'PP')
				goal_info = ptwa['presence'] >= goal['value_indicator'] ?
				{'indicator' => 1, 'value' => 'Cumplida'} : {'indicator' => -1, 'value' => ' No cumplida'}
			else
				goal_info = ptwa['ratio'] >= goal['value_indicator'] ?
				{'indicator' => 1, 'value' => 'Cumplida'} : {'indicator' => -1, 'value' => ' No cumplida'}
			end
			achieved_goal_waiters_count += 1 if (goal_info['value'] == 'Cumplida')

			# Obtener índice donde se encuentre almacenado la información del mesero
			# y en caso de existir completar la información correspondiente
			index = waiters_info_array.index {|wia| wia['uuid'] == ptwa['tag_id']}
			if (!index.nil?)
				waiters_info_array[index]['achieved_goal'] = (goal['indicator'] == 'PP' ?
					(ptwa['presence'] * 100).round(0) : ptwa['ratio'].round(1))
				waiters_info_array[index]['goal'] = goal_info
			end
		end

		# Validar que la información del arreglo waiters_info_array esté completa
		# y en caso contrario completarla. Adicional a esto agregar los meseros
		# faltantes al arreglo products_tags_waiters_array
		waiters_info_array.each do |wia|
			if (wia['goal'] == nil)
				# Completar información de la meta
				wia['goal'] = {'indicator' => -1, 'value' => ' No cumplida'}

				# Obtener información de referencia proveniente del arreglo 
				# products_tags_waiters_array o en su defecto del objeto goals
				reference = !products_tags_waiters_array.empty? ? products_tags_waiters_array[0] :
				{'category_branch' => goal['goal_products_tags'], 'category_name' => goal['goal_products_tags'][0]}
				
				# Crear estructura con la información del nuevo mesero por categoría
				# y agregarla al arreglo correspondiente
				new_waiter_by_product_tag = {
					'subtotal' => 0.0,
					'tax' => 0.0,
					'discount' => 0.0,
					'invoices' => 0,
					'articles' => 0,
					'client_count' => 0,
					'tag_id' => wia['uuid'],
					'tag_name' => wia['name'],
					'category_branch' => reference['category_branch'],
					'total' => 0.0,
					'average_price' => 0.0,
					'category_name' => reference['category_name'],
					'presence' => 0,
					'ratio' => 0.0
				}
				products_tags_waiters_array << new_waiter_by_product_tag
			end
		end

		# Ordenar el arreglo products_tags_waiters_array por el nuevo campo creado 
		# según sea el caso y el arreglo waiters_info_array por el campo goal['value']
		(goal['indicator'] == 'PP' ?
		products_tags_waiters_array.sort_by! {|item| -item['presence']} : products_tags_waiters_array.sort_by! {|item| -item['ratio']})
		waiters_info_array.sort_by! {|wia| wia['goal']['value']}

		# Obtener tamaño de ambos arreglos
		sales_waiters_array_length, products_tags_waiters_array_length = sales_waiters_array.length, products_tags_waiters_array.length

		# Agregar información de los mejores y peores meseros por vpc y por presencia
		# o radio de la etiqueta de producto de la meta
		while ((!sales_waiters_array.empty?) and (best_waiters_vpc.length != 3) and
			(worst_waiters_vpc.length != 3))
			# Obtener el número asociado al mesero que se va a agregar a la izquierda
			# y a la derecha
			waiter_position = (best_waiters_vpc.length + 1).to_s + '. '

			# Arreglos VPC. Validar si el tamaño del arreglo sea mayor a uno y en caso 
			# contrario guardar el único elemento existente en ambos arreglos
			if (sales_waiters_array_length == 1)
				# Obtener único elemento
				single_item = sales_waiters_array.shift

				# Definir objeto con la información del mesero común para ambos
				new_single_waiter = {
					'name' => waiter_position + single_item['tag_name'].strip.downcase.titleize.split(' ').join(' '),
					'vpc' => single_item['total_per_client'].round(2)
				}

				# Agregar objeto a ambos arreglos
				best_waiters_vpc << new_single_waiter
				worst_waiters_vpc << new_single_waiter
			else
				# Obtener el primer y último elemento del arreglo sales_waiters_array
				first_item, last_item = sales_waiters_array.shift, sales_waiters_array.pop

				# Validar que ambos elementos sean distintos de null, construir los objetos
				# correspondientes y agregarlos a sus respectivos arreglos
				if ((!first_item.nil?) and (!last_item.nil?))
					new_best_waiter = {
						'name' => waiter_position + first_item['tag_name'].strip.downcase.titleize.split(' ').join(' '),
						'vpc' => first_item['total_per_client'].round(2)
					}
					best_waiters_vpc << new_best_waiter

					new_worst_waiter = {
						'name' => waiter_position + last_item['tag_name'].strip.downcase.titleize.split(' ').join(' '),
						'vpc' => last_item['total_per_client'].round(2)
					}
					worst_waiters_vpc << new_worst_waiter
				end
			end

			# Arreglos Presencia/ Radio. Realizar las acciones anteriores para obtener la información
			# de los arreglos best_waiters_presence y worst_waiters_presence
			if (products_tags_waiters_array_length == 1)
				# Obtener único elemento
				single_item = products_tags_waiters_array.shift

				# Definir objeto con la información del mesero común para ambos arreglos
				new_single_waiter = {
					'name' => waiter_position + single_item['tag_name'].strip.downcase.titleize.split(' ').join(' '),
					'value' => ((goal['indicator'] == 'PP') ? (single_item['presence'] * 100).round(0).to_s + '%' : single_item['ratio'].round(1))
				}

				# Agregar objeto a anbos arreglos
				best_waiters_presence << new_single_waiter
				worst_waiters_presence << new_single_waiter
			else
				# Obtener el primer y último elemento del arreglo products_tags_waiters_array
				first_item, last_item = products_tags_waiters_array.shift, products_tags_waiters_array.pop

				# Validar que ambos elementos sean distintos de null, construir los objetos
				# correspondientes y agregarlos a sus respectivos arreglos
				if ((!first_item.nil?) and (!last_item.nil?))
					new_best_waiter = {
						'name' => waiter_position + first_item['tag_name'].strip.downcase.titleize.split(' ').join(' '),					
						'value' => ((goal['indicator'] == 'PP') ? (first_item['presence'] * 100).round(0).to_s + '%' : first_item['ratio'].round(1))
					}
					best_waiters_presence << new_best_waiter

					new_worst_waiter = {
						'name' => waiter_position + last_item['tag_name'].strip.downcase.titleize.split(' ').join(' '),
						'value' => ((goal['indicator'] == 'PP') ? (last_item['presence'] * 100).round(0).to_s + '%' : last_item['ratio'].round(1))
					}
					worst_waiters_presence << new_worst_waiter
				end
			end
		end

		# Crear 2 arreglos para almacenar las etiquetas de productos que se van a 
		# mostrar y obtener el valor del indicador que se usará como referencia
		products_tags_left, products_tags_right = [], []
		index_reference = (current_products_tags_hash.values.length / 2).round(0)
		
		# Llenar ambos arreglos modificando los datos correspondientes de ser el caso
		for i in (0..index_reference)
			# Obtener valor del arreglo current_products_tags_hash en la posición actual
			element = current_products_tags_hash.values[i][0]

			# Obtener índice de la etiqueta de la categoría asociada al patrón actual
			index = pattern['products_tags'].index {|item| item['name'] == element['name']}

			# Obtener valor de la variación para la presencia y el radio
			presence_variation = self.get_indicator_value(element['presence'], pattern['products_tags'][index]['base_presence'])
			ratio_variation = self.get_indicator_value(element['ratio'], pattern['products_tags'][index]['base_ratio'])

			# Crear nueva estructura
			new_product_tag = {
				'image' => element['image'],
				'name' => element['name'],
				'presence' => (element['presence'] * 100).round(0).to_s,
				'presence_variation' => presence_variation['value'],
				'ratio' => (element['ratio']).round(1).to_s,
				'ratio_variation' => ratio_variation['value'],
				'vpc' => element['vpc']
			}

			# Agregar al arreglo de la izquierda
			products_tags_left << new_product_tag
		end
		for i in ((index_reference + 1)..(current_products_tags_hash.values.length - 1))
			# Obtener valor del arreglo current_products_tags_hash en la posición actual
			element = current_products_tags_hash.values[i][0]

			# Obtener índice de la etiqueta de la categoría asociada al patrón actual
			index = pattern['products_tags'].index {|item| item['name'] == element['name']}

			# Obtener valor de la variación para la presencia y el radio
			presence_variation = self.get_indicator_value(element['presence'], pattern['products_tags'][index]['base_presence'])
			ratio_variation = self.get_indicator_value(element['ratio'], pattern['products_tags'][index]['base_ratio'])

			# Crear nueva estructura
			new_product_tag = {
				'image' => element['image'],
				'name' => element['name'],
				'presence' => (element['presence'] * 100).round(0).to_s,
				'presence_variation' => presence_variation['value'],
				'ratio' => (element['ratio']).round(1).to_s,
				'ratio_variation' => ratio_variation['value'],
				'vpc' => element['vpc']
			}

			# Agregar al arreglo de la derecha
			products_tags_right << new_product_tag
		end

		# Modificar valores del arreglo current_product_tag_array
		current_product_tag_array.each do |item|
			item['presence'] = (item['presence'] * 100).round(0).to_s + '%'
			item['ratio'] = (item['ratio']).round(1).to_s
		end
		
		# Llenar parte del objeto que se devolverá como respuesta
		pattern_params['waiters'] = achieved_goal_waiters_count.to_s + '/' + products_tags_waiters_array_length.to_s
		pattern_params['performance_goal'] = current_product_tag_array
		pattern_params['best_waiters_presence'] = best_waiters_presence
		pattern_params['worst_waiters_presence'] = worst_waiters_presence
		pattern_params['products_tags_left'] = products_tags_left
		pattern_params['products_tags_right'] = products_tags_right		
		pattern_params['weekly_vpc'] = sales_pattern_hash['total_per_client'].round(2)
		pattern_params['best_waiters_vpc'] = best_waiters_vpc
		pattern_params['worst_waiters_vpc'] = worst_waiters_vpc
		pattern_params['waiters_info'] = waiters_info_array

		# Obtener información del nivel de desempeño
		current_vpc = sales_pattern_hash['total_per_client']
		left_range = pattern['base_vpc'] - pattern['base_standard_deviation']
		rigth_range = pattern['base_vpc'] + pattern['base_standard_deviation']

		if (current_vpc <= left_range)
			pattern_params['performance_level'] = 'Deficiente'
		elsif ((left_range < current_vpc)  and (current_vpc <= pattern['base_vpc']))
			pattern_params['performance_level'] = 'Malo'			
		elsif ((pattern['base_vpc'] < current_vpc) and (current_vpc <= rigth_range))
			pattern_params['performance_level'] = 'Bueno'
		else		
			pattern_params['performance_level'] = 'Sobresaliente'
		end

		# Obtener información del incremento por comensal, el porcentaje de la semana
		# actual vs el de la base del patron y el incremento semanal para la semana actual
		pattern_params['incremental_vpc'] = (sales_pattern_hash['total_per_client'] - pattern['base_vpc']).round(2)
		pattern_params['incremental_vpc_per'] = self.get_indicator_value(pattern_params['incremental_vpc'], pattern['base_vpc'])
		pattern_params['weekly_increase'] = (pattern_params['incremental_vpc'] * sales_pattern_hash['client_count']).round(2)

		# Obtener información de las ventas del patrón de forma semanal y segmentando
		# las ventas mensualmente usando la fecha de referencia que tiene el patrón
		reference_date = pattern['reference_date'].beginning_of_week
		sales_pattern_cumulative_increase_array = WaiterGoal.get_general_waiter_information(locals,
			reference_date, end_date, pattern_taxonomy, false, filters, include_tags, 
			'weekly', exclude_taxes, goal['tag'], 'product-experience-tags', group, 'sales')['sales']

		# Agregar información de las vpc incrementales y sumarlas
		pattern_params['cumulative_increase'] = 0
		sales_pattern_cumulative_increase_array.each do |spcia|
			# Sumar vpc incremental
			pattern_params['cumulative_increase'] += ((spcia['total_per_client'] - pattern['base_vpc']) *
				spcia['client_count'])
		end

		# Obtener información de las últimas doce semanas, donde la última semana sea
		# la que se está evaluando. Ordenar el arreglo de mayor a menor
		sales_last_twelve_weeks_array =  WaiterGoal.get_general_waiter_information(locals,
			(end_date - 11.weeks), end_date, pattern_taxonomy, false, filters, include_tags,
			'weekly', exclude_taxes, goal['tag'], 'product-experience-tags', group, 'sales')['sales']
		sales_last_twelve_weeks_array.sort_by! {|item| [-item['time']['year'], -item['time']['week']]}

		# Definir objeto que almacenará la información de la gráfica
		pattern_params['highchart'] = {
			'base_vpc' => pattern['base_vpc'].round(2),
			'current_vpc' => sales_last_twelve_weeks_array[0]['total_per_client'].round(2),
			'dates' => [],			
			'historical_vpc' => [],
			'optimum_vpc' => pattern['optimum_vpc'].round(2)
		}

		# Obtener información de los primeros 12 elementos que se van a graficar en
		# el pdf
		for i in (0..11)
			if (!sales_last_twelve_weeks_array[i].nil?)
				# Obtener elemento del arreglo
				new_item = sales_last_twelve_weeks_array[i]

				# Agregar información de la vpc incremental
				pattern_params['highchart']['historical_vpc'].insert(0, new_item['total_per_client'].round(2))

				# Agregar información de la fecha
				date = Date.commercial(new_item['time']['year'], new_item['time']['week']).strftime('%d/%m')
				pattern_params['highchart']['dates'].insert(0, date)
			end
		end
	end

  # Actualiza las etiquetas de productos de los patrones asociados al grupo de
  # entrada agregando la imagen correspondiente según sea el caso.
  #
  # Parámetros del Método:
  # => group -- String : Identificador del grupo.
  #
  # => product_tag_name -- String : Nombre de la etiqueta de producto.
  #
  # => image -- String : Url de la imagen que se le va a cargar a la etiqueta de
  # => producto dada.
  #
  # Return: Un booleano o un string según sea el caso.
  #
  # Autor: José Barrientos
  # Modificado por: José Barrientos
  # Fecha de Modificación: 19/12/2019
	def self.load_pattern_image(group, product_tag_name, image)
		# Buscar todos los patrones asociados al grupo de entrada y que contengan el
		# nombre de la etiqueta de producto
		patterns_entries = Pattern.where({'group' => group, 'products_tags.name' => product_tag_name}).entries

		# Devolver mensaje si el arreglo patterns_entries es vacío
		if (!patterns_entries.empty?)
			# Definir arreglo que va a contener las actualizaciones de los patrones
			update_patterns = []

			# Recorrer el arreglo patterns_entries e ir construyendo la información que
			# se va a actualizar
			patterns_entries.each do |pattern_entry|
				# Definir nuevo arreglo que va a contener las actualizaciones de products_tags
				new_products_tags_array = []

				# Recorrer el arreglo de etiquetas de productos
				pattern_entry['products_tags'].each do |product_tag|
					# Crear nueva estructura en caso de que los nombres coincidan
					if (product_tag['name'] == product_tag_name)
						product_tag['image'] = image
					end

					# Agregar objeto actual al arreglo new_products_tags_array
					new_products_tags_array << product_tag
				end

		    # Construir el objeto que se utilizará para hacer la actualización y 
		    # agregarlo al arreglo update_patterns
		    aux = { update_one:
		    	{
		    		filter: { uuid: pattern_entry['uuid']},
		    		update: { :'$set' => {
		    			products_tags: new_products_tags_array
		    			}
		    		}
		    	}
		    }
		    update_patterns << aux
			end

			# Actualizar la colección correspondiente
			if (!update_patterns.empty?)
				Pattern.collection.bulk_write(update_patterns)
			end

			return true
		else
			return 'No existen patrones del grupo que contengan la etiqueta de producto definida.'
		end
	end
end
