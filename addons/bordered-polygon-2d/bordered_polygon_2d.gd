tool
extends 'abstract_bordered_polygon_2d.gd'
# Authors: Jonathan T. Arnold and Ary Pablo Batista

#!!!!!!!! to make borders work you must turn on repeat on textures

const QUAD_TOP_1    = 1
const QUAD_TOP_2    = 0
const QUAD_BOTTOM_1 = 3
const QUAD_BOTTOM_2 = 2

const SMOOTH_MAX_PASSES = 5
const SMOOTH_MIN_ANGLE = PI*0.08
const SMOOTH_MIN_ANGLE_GAIN = PI*0.08
const SMOOTH_MAX_NODES_PER_FACE = 10

var inner_polygon = null

var clockwise = null

onready var _is_ready = true

var borders = []

var editor_polygon_color = Color("ffffff")

func tileset_size(tileset):
	return tileset.get_tiles_ids().size()

func update():
	if _is_ready:
		# We only use polygon for edition purposes
		set_self_opacity(0)
		update_borders()

func invalidate():
	clockwise = null

func cross_product_z(a, b):
	# Cross product:
	#         | a1.b3 - a3.b2 |
	# a x b = | a3.b1 - a1.b3 |
	#         | a1.b2 - a2.b1 |
	#
	# We will take only third component
	# that will help us understand the
	# orientation of the shape
	return a.x * b.y - a.y * b.x

func is_clockwise_shape(shape):
	var shape_size = shape.size()
	if shape_size >= 3:
		var total = 0 
		for i in range(shape_size):
			var res = cross_product_z(shape[i], shape[(i + 1) % shape_size])
			total += res
		print(total)
		return total > 0
	else:
		return false

func is_clockwise():
	if clockwise == null:
		clockwise = is_clockwise_shape(get_polygon())
	return clockwise

func create_inner_polygon():
	var p = Polygon2D.new()
	p.set_texture(get_texture())
	p.set_texture_scale(get_texture_scale())
	p.set_texture_rotation(get_texture_rotation())
	p.set_texture_offset(get_texture_offset())
	p.set_uv(get_uv())
	p.set_color(editor_polygon_color)
	p.set_vertex_colors(get_vertex_colors())
	p.set_material(get_material())
	set_inner_polygon_node(p)

func set_inner_polygon_node(polygon):
	if inner_polygon != null:
		inner_polygon.free()
	inner_polygon = polygon
	add_child(inner_polygon)

func set_inner_polygon(polygon):
	if typeof(polygon) == TYPE_VECTOR2_ARRAY:
		create_inner_polygon()
		inner_polygon.set_polygon(polygon)
	else: # polygon is Polygon2D node
		set_inner_polygon_node(polygon)

func get_smooth_max_nodes():
	return get_polygon().size() * SMOOTH_MAX_NODES_PER_FACE * smooth_level

func get_smooth_max_angle():
	#var smooth_range = smooth_max_angle - SMOOTH_MIN_ANGLE
	#return abs(smooth_range * smooth_level + SMOOTH_MIN_ANGLE)
	# Input angle is in degrees
	return deg2rad(smooth_max_angle)

func triad_angle(a, b, c):
	var vector_ab = (b - a).normalized()
	var vector_bc = (c - b).normalized()
	return vector_ab.angle_to(vector_bc)

func smooth_shape_points(shape_points, max_angle):
	var original_points_count = shape_points.size()
	var new_smooth_points_count = 0
	for i in range(SMOOTH_MAX_PASSES): # max passes
		var point_to_smooth = []
		var angles_smoothed_this_round = 0
		var current_shape_size = shape_points.size()

		var round_new_points_count = 0
		for i in range(shape_points.size()):
			# b is the point to be smoothen
			# a and c are adyacent points
			var a = shape_points[(i + current_shape_size - 1) % current_shape_size]
			var b = shape_points[i]
			var c = shape_points[(i + 1) % current_shape_size]
			var triad_angle = abs(triad_angle(a, b, c))
			if triad_angle < max_angle:
				var smoothed_points = smooth_three_points(a, b, c)
				var obtained_angle = abs(triad_angle(smoothed_points[0], smoothed_points[1], smoothed_points[2]))
				var angle_gain = triad_angle - obtained_angle
				if angle_gain > SMOOTH_MIN_ANGLE_GAIN:
					round_new_points_count += smoothed_points.size()
					point_to_smooth.append([i, smoothed_points])

		if new_smooth_points_count + round_new_points_count >= get_smooth_max_nodes():
			break
		else:
			new_smooth_points_count += round_new_points_count
			
		var num_added_points = 0
		for point_info in point_to_smooth:
			shape_points.remove(point_info[0] + num_added_points)
			shape_points.insert(point_info[0] + num_added_points, point_info[1][2])
			shape_points.insert(point_info[0] + num_added_points, point_info[1][1])
			angles_smoothed_this_round += 1
			num_added_points += 1

		if angles_smoothed_this_round != 0 and shape_points.size() > 3:
			continue
		break

	return shape_points

func smooth_three_points(a, b, c):
	var vector_ba = a - b
	var vector_bc = c - b

	var splitted_b = [
		b + vector_ba.normalized() * (vector_ba.length()/4),
		b + vector_bc.normalized() * (vector_bc.length()/4)
	]

	var output_points = []
	output_points.append(a)
	for point in splitted_b:
		output_points.append(point)
	output_points.append(c)

	return output_points

func expand_or_contract_shape_points(shape_points, amount, advance=true):
		var points_count = shape_points.size()
		var expand_or_contract_amount = 0.0
		var output_points = []
		var point_normals = []
			
		for i in range(points_count):
			var a = shape_points[(i + points_count - 1) % points_count]
			var b = shape_points[i]
			var c = shape_points[(i + 1) % points_count]
			# get normals
			var subtractA_B = (b - a).normalized()
			var subtractC_B = (c - b).normalized()
			var a_90 = Vector2(subtractA_B.y, -subtractA_B.x)
			var c_90 = Vector2(subtractC_B.y, -subtractC_B.x)

			point_normals.append((a_90 + c_90).normalized()) 

		if advance == true:
			for test_point in range(points_count):
				var closet_point
				var closest_distance = abs(amount)
				var test_normal = [shape_points[test_point], amount * point_normals[test_point] + shape_points[test_point]]				
				for wall in range(points_count):
					if wall != test_point:
						var top_wall = [shape_points[wall],shape_points[(wall + 1) % points_count]]
						# get wall intersection
						var normal_and_wall_intersect = Geometry.segment_intersects_segment_2d(test_normal[0], test_normal[1], top_wall[0], top_wall[1])
						if normal_and_wall_intersect != null :
							var distance_from_test_point_to_intersetion = shape_points[test_point].distance_to(normal_and_wall_intersect)
							if distance_from_test_point_to_intersetion < closest_distance and distance_from_test_point_to_intersetion != 0:
								closest_distance = distance_from_test_point_to_intersetion
								closet_point =  normal_and_wall_intersect 
								
				var newVector
				if closest_distance != abs(amount):
					newVector = closet_point 
				else:
					newVector = point_normals[test_point] * amount + shape_points[test_point]
				output_points.append(newVector)	
		else:
			for i in range(points_count):
				output_points.append(point_normals[i] * amount + shape_points[i])

		return Vector2Array(output_points)

func add_border(border):
	add_child(border)
	borders.append(border)

func remove_borders():
	for border in borders:
		remove_child(border)
		border.free()
	borders = []

func possitive_angle(angle):
	if angle < 0:
		return PI*2 + angle
	else:
		return angle

func quad_angle(quad):
	# Vector for top quad segment
	var v = quad[QUAD_TOP_1] - quad[QUAD_TOP_2]

	# Perpendicular vector to the segment vector
	# This is the angle for the segment, the face angle
	var vp = Vector2(v.y, v.x * -1)

	# Make angle clockwise
	var angle = possitive_angle(PI*2 - vp.angle())
	return angle

func _360_partition(partition_count):
	return PI*2/partition_count

func partition_id(angle, partition_size):
	return int(rad2deg(angle) / rad2deg(partition_size))

func texture_idx_from_angle(tileset, angle):
	var texture_count = tileset_size(tileset)
	var partition_size = _360_partition(texture_count)
	var angle_offset = -partition_size/2
	var idx = partition_id(angle + angle_offset, partition_size) % texture_count
	idx = (idx + 1 - border_clockwise_shift) % texture_count
	if idx < 0: # Possitive indexes only
		idx = texture_count + idx
	return idx

func has_border_textures():
	return has_single_border_texture() or has_tileset_border_textures()

func has_single_border_texture():
	return border_texture != null

func has_tileset_border_textures():
	return border_textures != null and tileset_size(border_textures) >= 1

func invert_scale(scale):
	return Vector2(1/scale.x, 1/scale.y)

func create_border(width, height, quad, offset=Vector2(0,0)):
	var border = Polygon2D.new()
	var border_angle = quad_angle(quad)
	border.set_uv( [ Vector2(width, 0), Vector2(0, 0), Vector2(0, height), Vector2(width, height)])
	border.set_polygon(quad)
	border.set_texture_offset(offset)

	var tex_idx = 0
	if border_textures != null:
		tex_idx = texture_idx_from_angle(border_textures, border_angle)
	var tex = get_border_texture(tex_idx)
	tex.set_flags(tex.get_flags() | Texture.FLAG_REPEAT)
	border.set_texture(tex)
	if border_material != null:
		border.set_material(get_border_material(tex_idx))
	
	var texture_rotation = deg2rad(border_texture_rotation) + PI
	border.set_texture_rotation(texture_rotation)
	border.set_texture_scale(invert_scale(border_texture_scale))
	
	return border

func calculate_quad(index, points, border_points_count):
	# Quad order: [topRight, topLeft, bottomLeft, bottomRight]
	var quad = [
		points[(index + 1) % border_points_count],
		points[index % border_points_count],
		points[(index + border_points_count/2) % border_points_count],
		points[(index + border_points_count/2 + 1) % border_points_count]
	]

	# If quad twisted
	var intersect_point_1 = Geometry.segment_intersects_segment_2d(quad[0], quad[3], quad[1], quad[2])
	var intersect_point_2 = Geometry.segment_intersects_segment_2d(quad[1], quad[0], quad[2], quad[3])	
	if intersect_point_1 != null:
		quad = [quad[1], quad[0], quad[2], quad[3]]
	if intersect_point_2 != null:
		quad = [quad[2], quad[3], quad[1], quad[0]]
	
	return quad

func is_shape(shape_points):
	return shape_points.size() >= 3

func calculate_border_points(shape_points, border_size, border_overlap=0):
	var border_inner_points = shape_points
	var border_outer_points = expand_or_contract_shape_points(border_inner_points, border_size)

	# close outer shape
	border_inner_points.append(border_inner_points[0] + Vector2(0.0001, 0))
	for i in range(border_outer_points.size()):
		border_inner_points.append(border_outer_points[i])
	# close inner inner shape
	border_inner_points.append(border_outer_points[0] + Vector2(0, 0.0001))
	return border_inner_points

func get_border_material(idx):
	if border_textures != null:
		return border_textures.tile_get_material(idx)
	else:
		return border_material

func get_border_texture(idx=0):
	if border_textures != null:
		return border_textures.tile_get_texture(idx)
	else:
		return border_texture

func get_texture_sample():
	return get_border_texture(0)

func max_quad_width(quad):
	var top_width = quad[QUAD_TOP_1].distance_to(quad[QUAD_TOP_2])
	var bottom_width = quad[QUAD_BOTTOM_1].distance_to(quad[QUAD_BOTTOM_2])
	return max(top_width, bottom_width)

func make_border(border_size):
	var shape_points = get_polygon()
	
	if not is_clockwise_shape(shape_points):
		shape_points.invert()

	if smooth_level > 0:
		shape_points = smooth_shape_points(shape_points, get_smooth_max_angle())
	
	set_inner_polygon(expand_or_contract_shape_points(shape_points, border_size + border_overlap))
	var border_points = calculate_border_points(shape_points, border_size, border_overlap)

	# Turn points to quads
	var lastborder_texture_offset = 0
	var border_points_count = border_points.size()
	var texture_sample = get_texture_sample()
	var sample_width = texture_sample.get_size().x

	for i in range(border_points_count/2 - 1):
		var quad = calculate_quad(i, border_points, border_points_count)
		var width = max_quad_width(quad)
		var border = create_border(width, border_size, quad, Vector2(lastborder_texture_offset + border_texture_offset.x, border_texture_offset.y))
		lastborder_texture_offset = width + lastborder_texture_offset
		add_border(border)

func update_borders():
	# store editor polygon color
	if editor_polygon_color != Color("00ffffff"):
		editor_polygon_color = get_color()
	
	# Remove old borders
	remove_borders()
	if is_shape(get_polygon()) and has_border_textures():
		make_border(border_size)
	
	# hide control polygon when running
	if get_tree().is_editor_hint() == false:
		set_color("00ffffff")

func _ready():
	update()
