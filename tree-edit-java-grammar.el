;;; tree-edit-java-grammar.el --- Description -*- lexical-binding: t; -*-
;;
;; Copyright (C) 2021 Ethan Leba
;;
;; This file is not part of GNU Emacs.
;;
;;; Commentary:
;;
;;; Code:
(require 'mode-local)

(tree-edit-load-grammar "tests/java-grammar" java-mode)

(setq-mode-local
 java-mode

 tree-edit--supertypes
 '((program program)
   (_literal _literal primary_expression primary_expression expression expression _element_value _element_value _variable_initializer _variable_initializer)
   (decimal_integer_literal decimal_integer_literal _literal _literal primary_expression primary_expression expression expression _element_value _element_value _variable_initializer _variable_initializer)
   (hex_integer_literal hex_integer_literal _literal _literal primary_expression primary_expression expression expression _element_value _element_value _variable_initializer _variable_initializer)
   (octal_integer_literal octal_integer_literal _literal _literal primary_expression primary_expression expression expression _element_value _element_value _variable_initializer _variable_initializer)
   (binary_integer_literal binary_integer_literal _literal _literal primary_expression primary_expression expression expression _element_value _element_value _variable_initializer _variable_initializer)
   (decimal_floating_point_literal decimal_floating_point_literal _literal _literal primary_expression primary_expression expression expression _element_value _element_value _variable_initializer _variable_initializer)
   (hex_floating_point_literal hex_floating_point_literal _literal _literal primary_expression primary_expression expression expression _element_value _element_value _variable_initializer _variable_initializer)
   (true true _literal _literal primary_expression primary_expression expression expression _element_value _element_value _variable_initializer _variable_initializer)
   (false false _literal _literal primary_expression primary_expression expression expression _element_value _element_value _variable_initializer _variable_initializer)
   (character_literal character_literal _literal _literal primary_expression primary_expression expression expression _element_value _element_value _variable_initializer _variable_initializer)
   (string_literal string_literal _literal _literal primary_expression primary_expression expression expression _element_value _element_value _variable_initializer _variable_initializer)
   (null_literal null_literal _literal _literal primary_expression primary_expression expression expression _element_value _element_value _variable_initializer _variable_initializer)
   (expression expression _element_value _element_value _variable_initializer _variable_initializer)
   (cast_expression cast_expression expression expression _element_value _element_value _variable_initializer _variable_initializer)
   (assignment_expression assignment_expression expression expression _element_value _element_value _variable_initializer _variable_initializer)
   (binary_expression binary_expression expression expression _element_value _element_value _variable_initializer _variable_initializer)
   (instanceof_expression instanceof_expression expression expression _element_value _element_value _variable_initializer _variable_initializer)
   (lambda_expression lambda_expression expression expression _element_value _element_value _variable_initializer _variable_initializer)
   (inferred_parameters inferred_parameters)
   (ternary_expression ternary_expression expression expression _element_value _element_value _variable_initializer _variable_initializer)
   (unary_expression unary_expression expression expression _element_value _element_value _variable_initializer _variable_initializer)
   (update_expression update_expression expression expression _element_value _element_value _variable_initializer _variable_initializer)
   (primary_expression primary_expression expression expression _element_value _element_value _variable_initializer _variable_initializer)
   (array_creation_expression array_creation_expression primary_expression primary_expression expression expression _element_value _element_value _variable_initializer _variable_initializer)
   (dimensions_expr dimensions_expr)
   (parenthesized_expression parenthesized_expression primary_expression primary_expression expression expression _element_value _element_value _variable_initializer _variable_initializer)
   (class_literal class_literal primary_expression primary_expression expression expression _element_value _element_value _variable_initializer _variable_initializer)
   (object_creation_expression object_creation_expression primary_expression primary_expression expression expression _element_value _element_value _variable_initializer _variable_initializer)
   (_unqualified_object_creation_expression _unqualified_object_creation_expression object_creation_expression object_creation_expression primary_expression primary_expression expression expression _element_value _element_value _variable_initializer _variable_initializer)
   (field_access field_access primary_expression primary_expression expression expression _element_value _element_value _variable_initializer _variable_initializer resource resource)
   (array_access array_access primary_expression primary_expression expression expression _element_value _element_value _variable_initializer _variable_initializer)
   (method_invocation method_invocation primary_expression primary_expression expression expression _element_value _element_value _variable_initializer _variable_initializer)
   (argument_list argument_list)
   (method_reference method_reference primary_expression primary_expression expression expression _element_value _element_value _variable_initializer _variable_initializer)
   (type_arguments type_arguments)
   (wildcard wildcard)
   (_wildcard_bounds _wildcard_bounds)
   (dimensions dimensions)
   (switch_expression switch_expression expression expression _element_value _element_value _variable_initializer _variable_initializer statement statement program program)
   (switch_block switch_block)
   (switch_block_statement_group switch_block_statement_group)
   (switch_rule switch_rule)
   (switch_label switch_label)
   (statement statement program program)
   (block block statement statement program program _class_body_declaration _class_body_declaration)
   (expression_statement expression_statement statement statement program program)
   (labeled_statement labeled_statement statement statement program program)
   (assert_statement assert_statement statement statement program program)
   (do_statement do_statement statement statement program program)
   (break_statement break_statement statement statement program program)
   (continue_statement continue_statement statement statement program program)
   (return_statement return_statement statement statement program program)
   (yield_statement yield_statement statement statement program program)
   (synchronized_statement synchronized_statement statement statement program program)
   (throw_statement throw_statement statement statement program program)
   (try_statement try_statement statement statement program program)
   (catch_clause catch_clause)
   (catch_formal_parameter catch_formal_parameter)
   (catch_type catch_type)
   (finally_clause finally_clause)
   (try_with_resources_statement try_with_resources_statement statement statement program program)
   (resource_specification resource_specification)
   (resource resource)
   (if_statement if_statement statement statement program program)
   (while_statement while_statement statement statement program program)
   (for_statement for_statement statement statement program program)
   (enhanced_for_statement enhanced_for_statement statement statement program program)
   (_annotation _annotation _element_value _element_value modifiers modifiers)
   (marker_annotation marker_annotation _annotation _annotation _element_value _element_value modifiers modifiers)
   (annotation annotation _annotation _annotation _element_value _element_value modifiers modifiers)
   (annotation_argument_list annotation_argument_list)
   (element_value_pair element_value_pair)
   (_element_value _element_value)
   (element_value_array_initializer element_value_array_initializer _element_value _element_value)
   (declaration declaration statement statement program program)
   (module_declaration module_declaration declaration declaration statement statement program program)
   (module_body module_body)
   (module_directive module_directive)
   (requires_modifier requires_modifier)
   (package_declaration package_declaration declaration declaration statement statement program program)
   (import_declaration import_declaration declaration declaration statement statement program program)
   (asterisk asterisk)
   (enum_declaration enum_declaration declaration declaration statement statement program program _class_body_declaration _class_body_declaration)
   (enum_body enum_body)
   (enum_body_declarations enum_body_declarations)
   (enum_constant enum_constant)
   (class_declaration class_declaration declaration declaration statement statement program program _class_body_declaration _class_body_declaration)
   (modifiers modifiers)
   (type_parameters type_parameters)
   (type_parameter type_parameter)
   (type_bound type_bound)
   (superclass superclass)
   (super_interfaces super_interfaces)
   (interface_type_list interface_type_list)
   (class_body class_body)
   (_class_body_declaration _class_body_declaration)
   (static_initializer static_initializer _class_body_declaration _class_body_declaration)
   (constructor_declaration constructor_declaration _class_body_declaration _class_body_declaration)
   (_constructor_declarator _constructor_declarator)
   (constructor_body constructor_body)
   (explicit_constructor_invocation explicit_constructor_invocation)
   (_name _name)
   (scoped_identifier scoped_identifier _name _name)
   (field_declaration field_declaration _class_body_declaration _class_body_declaration)
   (record_declaration record_declaration _class_body_declaration _class_body_declaration)
   (annotation_type_declaration annotation_type_declaration declaration declaration statement statement program program _class_body_declaration _class_body_declaration)
   (annotation_type_body annotation_type_body)
   (annotation_type_element_declaration annotation_type_element_declaration)
   (_default_value _default_value)
   (interface_declaration interface_declaration declaration declaration statement statement program program _class_body_declaration _class_body_declaration)
   (extends_interfaces extends_interfaces)
   (interface_body interface_body)
   (constant_declaration constant_declaration)
   (_variable_declarator_list _variable_declarator_list)
   (variable_declarator variable_declarator _variable_declarator_list _variable_declarator_list)
   (_variable_declarator_id _variable_declarator_id variable_declarator variable_declarator _variable_declarator_list _variable_declarator_list)
   (_variable_initializer _variable_initializer)
   (array_initializer array_initializer _variable_initializer _variable_initializer)
   (_type _type interface_type_list interface_type_list)
   (_unannotated_type _unannotated_type catch_type catch_type _type _type interface_type_list interface_type_list)
   (_simple_type _simple_type _unannotated_type _unannotated_type catch_type catch_type _type _type interface_type_list interface_type_list)
   (annotated_type annotated_type _type _type interface_type_list interface_type_list)
   (scoped_type_identifier scoped_type_identifier _simple_type _simple_type _unannotated_type _unannotated_type catch_type catch_type _type _type interface_type_list interface_type_list)
   (generic_type generic_type _simple_type _simple_type _unannotated_type _unannotated_type catch_type catch_type _type _type interface_type_list interface_type_list)
   (array_type array_type _unannotated_type _unannotated_type catch_type catch_type _type _type interface_type_list interface_type_list)
   (integral_type integral_type _simple_type _simple_type _unannotated_type _unannotated_type catch_type catch_type _type _type interface_type_list interface_type_list)
   (floating_point_type floating_point_type _simple_type _simple_type _unannotated_type _unannotated_type catch_type catch_type _type _type interface_type_list interface_type_list)
   (boolean_type boolean_type _simple_type _simple_type _unannotated_type _unannotated_type catch_type catch_type _type _type interface_type_list interface_type_list)
   (void_type void_type _simple_type _simple_type _unannotated_type _unannotated_type catch_type catch_type _type _type interface_type_list interface_type_list)
   (_method_header _method_header)
   (_method_declarator _method_declarator)
   (formal_parameters formal_parameters)
   (formal_parameter formal_parameter)
   (receiver_parameter receiver_parameter)
   (spread_parameter spread_parameter)
   (throws throws)
   (local_variable_declaration local_variable_declaration statement statement program program)
   (method_declaration method_declaration _class_body_declaration _class_body_declaration)
   (_reserved_identifier _reserved_identifier primary_expression primary_expression expression expression _element_value _element_value _variable_initializer _variable_initializer _name _name _variable_declarator_id _variable_declarator_id variable_declarator variable_declarator _variable_declarator_list _variable_declarator_list)
   (this this primary_expression primary_expression expression expression _element_value _element_value _variable_initializer _variable_initializer)
   (super super)
   (identifier identifier primary_expression primary_expression expression expression _element_value _element_value _variable_initializer _variable_initializer resource resource enum_constant enum_constant type_parameter type_parameter _name _name _variable_declarator_id _variable_declarator_id variable_declarator variable_declarator _variable_declarator_list _variable_declarator_list _simple_type _simple_type _unannotated_type _unannotated_type catch_type catch_type _type _type interface_type_list interface_type_list)
   (comment comment))
 tree-edit--containing-types
 '((program statement)
   (_literal decimal_integer_literal hex_integer_literal octal_integer_literal binary_integer_literal decimal_floating_point_literal hex_floating_point_literal true false character_literal string_literal null_literal)
   (decimal_integer_literal)
   (hex_integer_literal)
   (octal_integer_literal)
   (binary_integer_literal)
   (decimal_floating_point_literal)
   (hex_floating_point_literal)
   (true)
   (false)
   (character_literal)
   (string_literal)
   (null_literal)
   (expression assignment_expression binary_expression instanceof_expression lambda_expression ternary_expression update_expression primary_expression unary_expression cast_expression switch_expression)
   (cast_expression _type _type expression)
   (assignment_expression identifier _reserved_identifier field_access array_access expression)
   (binary_expression expression expression expression expression expression expression expression expression expression expression expression expression expression expression expression expression expression expression expression expression expression expression expression expression expression expression expression expression expression expression expression expression expression expression expression expression expression expression)
   (instanceof_expression expression _type)
   (lambda_expression identifier formal_parameters inferred_parameters expression block)
   (inferred_parameters identifier identifier)
   (ternary_expression expression expression expression)
   (unary_expression expression expression expression expression)
   (update_expression expression expression expression expression)
   (primary_expression _literal class_literal this identifier _reserved_identifier parenthesized_expression object_creation_expression field_access array_access method_invocation method_reference array_creation_expression)
   (array_creation_expression _simple_type dimensions_expr dimensions dimensions array_initializer)
   (dimensions_expr _annotation expression)
   (parenthesized_expression expression)
   (class_literal _unannotated_type)
   (object_creation_expression _unqualified_object_creation_expression primary_expression _unqualified_object_creation_expression)
   (_unqualified_object_creation_expression type_arguments _simple_type argument_list class_body)
   (field_access primary_expression super super identifier _reserved_identifier this)
   (array_access primary_expression expression)
   (method_invocation identifier _reserved_identifier primary_expression super super type_arguments identifier _reserved_identifier argument_list)
   (argument_list expression expression)
   (method_reference _type primary_expression super type_arguments identifier)
   (type_arguments _type wildcard _type wildcard)
   (wildcard _annotation _wildcard_bounds)
   (_wildcard_bounds _type super _type)
   (dimensions _annotation)
   (switch_expression parenthesized_expression switch_block)
   (switch_block switch_block_statement_group switch_rule)
   (switch_block_statement_group switch_label statement)
   (switch_rule switch_label expression_statement throw_statement block)
   (switch_label expression expression)
   (statement declaration expression_statement labeled_statement if_statement while_statement for_statement enhanced_for_statement block assert_statement do_statement break_statement continue_statement return_statement yield_statement switch_expression synchronized_statement local_variable_declaration throw_statement try_statement try_with_resources_statement)
   (block statement)
   (expression_statement expression)
   (labeled_statement identifier statement)
   (assert_statement expression expression expression)
   (do_statement statement parenthesized_expression)
   (break_statement identifier)
   (continue_statement identifier)
   (return_statement expression)
   (yield_statement expression)
   (synchronized_statement parenthesized_expression block)
   (throw_statement expression)
   (try_statement block catch_clause catch_clause finally_clause)
   (catch_clause catch_formal_parameter block)
   (catch_formal_parameter modifiers catch_type _variable_declarator_id)
   (catch_type _unannotated_type _unannotated_type)
   (finally_clause block)
   (try_with_resources_statement resource_specification block catch_clause finally_clause)
   (resource_specification resource resource)
   (resource modifiers _unannotated_type _variable_declarator_id expression identifier field_access)
   (if_statement parenthesized_expression statement statement)
   (while_statement parenthesized_expression statement)
   (for_statement local_variable_declaration expression expression expression expression expression statement)
   (enhanced_for_statement modifiers _unannotated_type _variable_declarator_id expression statement)
   (_annotation marker_annotation annotation)
   (marker_annotation _name)
   (annotation _name annotation_argument_list)
   (annotation_argument_list _element_value element_value_pair element_value_pair)
   (element_value_pair identifier _element_value)
   (_element_value expression element_value_array_initializer _annotation)
   (element_value_array_initializer _element_value _element_value)
   (declaration module_declaration package_declaration import_declaration class_declaration interface_declaration annotation_type_declaration enum_declaration)
   (module_declaration _annotation _name module_body)
   (module_body module_directive)
   (module_directive requires_modifier _name _name _name _name _name _name _name _name _name _name _name)
   (requires_modifier)
   (package_declaration _annotation _name)
   (import_declaration _name asterisk)
   (asterisk)
   (enum_declaration modifiers identifier super_interfaces enum_body)
   (enum_body enum_constant enum_constant enum_body_declarations)
   (enum_body_declarations _class_body_declaration)
   (enum_constant modifiers identifier argument_list class_body)
   (class_declaration modifiers identifier type_parameters superclass super_interfaces class_body)
   (modifiers _annotation)
   (type_parameters type_parameter type_parameter)
   (type_parameter _annotation identifier type_bound)
   (type_bound _type _type)
   (superclass _type)
   (super_interfaces interface_type_list)
   (interface_type_list _type _type)
   (class_body _class_body_declaration)
   (_class_body_declaration field_declaration record_declaration method_declaration class_declaration interface_declaration annotation_type_declaration enum_declaration block static_initializer constructor_declaration)
   (static_initializer block)
   (constructor_declaration modifiers _constructor_declarator throws constructor_body)
   (_constructor_declarator type_parameters identifier formal_parameters)
   (constructor_body explicit_constructor_invocation statement)
   (explicit_constructor_invocation type_arguments this super primary_expression type_arguments super argument_list)
   (_name identifier _reserved_identifier scoped_identifier)
   (scoped_identifier _name identifier)
   (field_declaration modifiers _unannotated_type _variable_declarator_list)
   (record_declaration modifiers identifier formal_parameters class_body)
   (annotation_type_declaration modifiers identifier annotation_type_body)
   (annotation_type_body annotation_type_element_declaration constant_declaration class_declaration interface_declaration annotation_type_declaration)
   (annotation_type_element_declaration modifiers _unannotated_type identifier dimensions _default_value)
   (_default_value _element_value)
   (interface_declaration modifiers identifier type_parameters extends_interfaces interface_body)
   (extends_interfaces interface_type_list)
   (interface_body constant_declaration enum_declaration method_declaration class_declaration interface_declaration annotation_type_declaration)
   (constant_declaration modifiers _unannotated_type _variable_declarator_list)
   (_variable_declarator_list variable_declarator variable_declarator)
   (variable_declarator _variable_declarator_id _variable_initializer)
   (_variable_declarator_id identifier _reserved_identifier dimensions)
   (_variable_initializer expression array_initializer)
   (array_initializer _variable_initializer _variable_initializer)
   (_type _unannotated_type annotated_type)
   (_unannotated_type _simple_type array_type)
   (_simple_type void_type integral_type floating_point_type boolean_type identifier scoped_type_identifier generic_type)
   (annotated_type _annotation _unannotated_type)
   (scoped_type_identifier identifier scoped_type_identifier generic_type _annotation identifier)
   (generic_type identifier scoped_type_identifier type_arguments)
   (array_type _unannotated_type dimensions)
   (integral_type)
   (floating_point_type)
   (boolean_type)
   (void_type)
   (_method_header type_parameters _annotation _unannotated_type _method_declarator throws)
   (_method_declarator identifier _reserved_identifier formal_parameters dimensions)
   (formal_parameters receiver_parameter formal_parameter spread_parameter formal_parameter spread_parameter)
   (formal_parameter modifiers _unannotated_type _variable_declarator_id)
   (receiver_parameter _annotation _unannotated_type identifier this)
   (spread_parameter modifiers _unannotated_type variable_declarator)
   (throws _type _type)
   (local_variable_declaration modifiers _unannotated_type _variable_declarator_list)
   (method_declaration modifiers _method_header block)
   (_reserved_identifier)
   (this)
   (super)
   (identifier)
   (comment)))

(provide 'tree-edit-java-grammar)
;;; tree-edit-java-grammar.el ends here