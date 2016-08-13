
open Ast
open Type
open Common
open Meta

(* Check lists:
tclass = {
	[x] mutable cl_path : path;
	[ ] mutable cl_module : module_def;
	[ ] mutable cl_pos : Ast.pos;
	[ ] mutable cl_private : bool;
	[ ] mutable cl_doc : Ast.documentation;
	[ ] mutable cl_meta : metadata;
	[ ] mutable cl_params : type_params;
	[ ] mutable cl_kind : tclass_kind;
	[ ] mutable cl_extern : bool;
	[x] mutable cl_interface : bool;
	[x] mutable cl_super : (tclass * tparams) option;
	[x] mutable cl_implements : (tclass * tparams) list;
	[ ] mutable cl_fields : (string , tclass_field) PMap.t;
	[ ] mutable cl_statics : (string, tclass_field) PMap.t;
	[ ] mutable cl_ordered_statics : tclass_field list;
	[ ] mutable cl_ordered_fields : tclass_field list;
	[ ] mutable cl_dynamic : t option;
	[ ] mutable cl_array_access : t option;
	[ ] mutable cl_constructor : tclass_field option;
	[ ] mutable cl_init : texpr option;
	[ ] mutable cl_overrides : tclass_field list;
	[ ] mutable cl_build : unit -> build_state;
	[ ] mutable cl_restore : unit -> unit;
}

*)

let follow = Abstract.follow_with_abstracts

(**
	@return `opt` value or `default` if `opt` is None
*)
let get_option_value (opt:'a option) default =
	match opt with
		| None -> default
		| Some value -> value

(**
	@param path Something like [ "/some/path/first_dir_to_create"; "nested_level1"; "nested_level2" ]
	@return String representation of created path (E.g. "/some/path/first_dir_to_create/nested_level1/nested_level2")
*)
let create_dir_recursive (path:string list) =
	let rec create dir nested_dirs =
		if not (Sys.file_exists dir) then (Unix.mkdir dir 0o755);
		match nested_dirs with
			| [] -> ();
			| next :: rest -> create (dir ^ "/" ^ next) rest
	in
	match path with
		| [] -> "";
		| root :: rest ->
			create root rest;
			(String.concat "/" path)

(**
	@return String representation of specified type path. E.g. returns "\example\Test" for (["example"], "Test")
*)
let get_full_type_name (type_path:path) =
	match type_path with
		| (module_path, type_name) -> (String.concat "\\" ("" :: module_path)) ^ "\\" ^ type_name

(**
	@return Short type name. E.g. returns "Test" for (["example"], "Test")
*)
let get_type_name (type_path:path) = match type_path with (_, type_name) -> type_name

(**
	@return E.g. returns ["example"] for (["example"], "Test")
*)
let get_module_path (type_path:path) = match type_path with (module_path, _) -> module_path

(**
	Extract native type path from @:native metadata (if exists)
*)
let get_native_path (meta:metadata) =
	try
		let entry = Meta.get Meta.Native meta in
		match entry with
			| (Native, [(EConst (String str_path), _)], _) ->
				let build_path parts =
					let reversed = List.rev parts in
					Some (List.rev (List.tl reversed), List.hd reversed)
				in
				(match Str.split (Str.regexp "\\") (String.trim str_path) with
					| "" :: [] -> failwith ("Invalid @:native value: " ^ str_path)
					| "" :: parts -> build_path parts
					| parts -> build_path parts
				)
			| _ -> failwith "Invalid @:native meta"
	with
		| Not_found -> None
		| e -> raise e

(**
	@return PHP visibility keyword.
*)
let get_visibility (meta:metadata) = if Meta.has Meta.Protected meta then "protected" else "public"

(**
	PHP DocBlock types
*)
type doc_type =
	| DocVar of string * (string option) (* (type name, description) *)
	| DocMethod of (string * bool * t) list * t * (string option) (* (arguments, return type, description) *)
	| DocClass of string option

(**
	Common interface for module_type instances
*)
class virtual type_wrapper (haxe_path:path) (meta:metadata) (needs_generation:bool) =
	object (self)
		val mutable allow_private_calls = false
		val mutable allow_private_vars = false
		val mutable native_path = None
		(**
			Indicates if this type should be rendered to corresponding php file
		*)
		method needs_generation = needs_generation
		(**
			Indicates if third party types call private methods of this type
		*)
		method allows_private_calls = allow_private_calls;
		(**
			Indicates if third party types access private vars of this type
		*)
		method allows_private_vars_access = allow_private_vars;
		(**
			Makes this class type private methods accessible by third party types
		*)
		method enable_private_calls = allow_private_calls <- true;
		(**
			Makes this class type private variables accessible by third party types
		*)
		method enable_private_vars_access = allow_private_vars <- true;
		(**
			Native namespace path in PHP
		*)
		method get_namespace = get_module_path self#get_native_path
		(**
			Native type path in PHP
		*)
		method get_native_path =
			match native_path with
				| Some path -> path
				| None ->
					let path =
						match (get_native_path meta) with
							| Some path -> path
							| None -> haxe_path
					in
					native_path <- Some path;
					path
	end

(**
	TClassDecl
*)
class class_wrapper (cls) =
	object (self)
		inherit type_wrapper cls.cl_path cls.cl_meta (not cls.cl_extern)
	end

(**
	TEnumDecl
*)
class enum_wrapper (enm) =
	object (self)
		inherit type_wrapper enm.e_path enm.e_meta (not enm.e_extern)
	end

(**
	TTypeDecl
*)
class typedef_wrapper (tdef) =
	object (self)
		inherit type_wrapper tdef.t_path tdef.t_meta false
	end

(**
	TAbstractDecl
*)
class abstract_wrapper (abstr) =
	object (self)
		inherit type_wrapper abstr.a_path abstr.a_meta false
	end

(**
	type_wrapper for classes
*)
let classes = Hashtbl.create 1000
let get_class_wrapper cls  : type_wrapper =
	try
		let wrapper = Hashtbl.find classes cls in
		wrapper
	with
		| Not_found ->
			let wrapper = new class_wrapper cls in
			Hashtbl.add classes cls wrapper;
			wrapper
		| e -> raise e

(**
	type_wrapper for enums
*)
let enums = Hashtbl.create 200
let get_enum_wrapper enm : type_wrapper=
	try
		let wrapper = Hashtbl.find enums enm in
		wrapper
	with
		| Not_found ->
			let wrapper = new enum_wrapper enm in
			Hashtbl.add enums enm wrapper;
			wrapper
		| e -> raise e

(**
	type_wrapper for typedefs
*)
let typedefs = Hashtbl.create 200
let get_typedef_wrapper typedef : type_wrapper =
	try
		let wrapper = Hashtbl.find typedefs typedef in
		wrapper
	with
		| Not_found ->
			let wrapper = new typedef_wrapper typedef in
			Hashtbl.add typedefs typedef wrapper;
			wrapper
		| e -> raise e

(**
	type_wrapper for abstracts
*)
let abstracts = Hashtbl.create 200
let get_abstract_wrapper abstr : type_wrapper =
	try
		let wrapper = Hashtbl.find abstracts abstr in
		wrapper
	with
		| Not_found ->
			let wrapper = new abstract_wrapper abstr in
			Hashtbl.add abstracts abstr wrapper;
			wrapper
		| e -> raise e

(**
	Returns wrapper for module_type.
	Caches wrappers so that each type will always return the same wrapper instance.
*)
let get_wrapper (mtype:module_type) : type_wrapper =
	match mtype with
		| TClassDecl cls -> get_class_wrapper cls
		| TEnumDecl enm -> get_enum_wrapper enm
		| TTypeDecl typedef -> get_typedef_wrapper typedef
		| TAbstractDecl abstr -> get_abstract_wrapper abstr

(**
	Base class for type builders
*)
class virtual type_builder wrapper =
	object (self)
		(** This is required to make wrapper accessible by extending classes *)
		val wrapper = wrapper
		(** List of types for "use" section *)
		val use_table = Hashtbl.create 50
		(** Output buffer *)
		val buffer = Buffer.create 1024
		(** Cache for generated conent *)
		val mutable contents = ""
		(** intendation used for each line written *)
		val mutable indentation = ""
		(**
			Get PHP namespace path
		*)
		method get_namespace = wrapper#get_namespace
		(**
			Get type name
		*)
		method get_name = get_type_name wrapper#get_native_path
		(**
			Writes type declaration line to output buffer.
			E.g. "class SomeClass extends Another implements IFace"
		*)
		method virtual private write_declaration : unit
		(**
			Writes type body to output buffer.
			E.g. for "class SomeClass { <BODY> }" writes <BODY> part.
		*)
		method virtual private write_body : unit
		(**
			Increase indentation by one level
		*)
		method indent_more =
			indentation <- indentation ^ "\t";
		(**
			Decrease indentation by one level
		*)
		method indent_less =
			indentation <- String.make ((String.length indentation) - 1) '\t';
		(**
			Set indentation level (starting from zero for no indentation)
		*)
		method indent level =
			indentation <- String.make level '\t';
		(**
			Returns generated file contents
		*)
		method get_contents =
			if (String.length contents) = 0 then begin
				self#write_declaration;
				self#indent 0;
				self#write_line "{";
				self#write_body;
				self#indent 0;
				self#write_line "}";
				let body = Buffer.contents buffer in
				Buffer.clear buffer;
				self#write_header;
				self#write "\n";
				let header = Buffer.contents buffer in
				contents <- header ^ body;
			end;
			contents
		(**
			Adds type to "use" section if not added yet.
			If it's a top-level type then type name returned without adding to "use" section.
			@return Unique alias for specified type.
		*)
		method use (type_path:path) =
			let module_path = get_module_path type_path in
			match type_path with
				| ([], type_name) -> "\\" ^ type_name
				| _ ->
					let alias_source = ref (List.rev module_path) in
					let get_alias_next_part () =
						match !alias_source with
							| [] -> failwith ("Failed to find already used type: " ^ get_full_type_name type_path)
							| name :: rest ->
								alias_source := rest;
								String.capitalize name
					and added = ref false
					and alias = ref (get_type_name type_path) in
					while not !added do
						try
							let used_type = Hashtbl.find use_table !alias in
							if used_type = type_path then
								added := true
							else
								alias := get_alias_next_part () ^ !alias;
						with
							| Not_found ->
								Hashtbl.add use_table !alias type_path;
								added := true
							| _ -> failwith "Unknown"
					done;
					!alias
		(**
			Extracts type path from Type.t value and execute self#use on it
			@return Unique alias for specified type.
		*)
		method use_t (t_inst:Type.t) =
			match follow t_inst with
				| TEnum (tenum, _) -> self#use tenum.e_path
				| TInst (tcls, _) ->
					(
						match tcls.cl_path with
							| ([], "String") -> "string"
							| _ -> self#use tcls.cl_path
					)
				| TFun _ -> self#use ([], "Closure")
				| TAnon _ -> "object"
				| TDynamic _ -> "mixed"
				| TLazy _ -> failwith "TLazy not implemented"
				| TMono mono ->
					(
						match !mono with
							| None -> "mixed"
							| Some t -> self#use_t t
					)
				| TType _ -> failwith "TType not implemented"
				| TAbstract (abstr, _) ->
					match abstr.a_path with
						| ([],"Int") -> "int"
						| ([],"Float") -> "float"
						| ([],"Bool") -> "bool"
						| ([],"Void") -> "void"
						| _ -> self#use_t abstr.a_this
		(**
			Writes specified string to output buffer
		*)
		method private write str =
			Buffer.add_string buffer str
		(**
			Writes fixed amount of empty lines (E.g. between methods)
		*)
		method private write_empty_lines =
			self#write "\n";
			self#write "\n"
		(**
			Writes current indentation to output buffer
		*)
		method private write_indentation =
			Buffer.add_string buffer indentation
		(**
			Writes specified line to output buffer and appends \n
		*)
		method private write_line line =
			Buffer.add_string buffer (indentation ^ line ^ "\n")
		(**
			Writes specified statement to output buffer and appends ";\n"
		*)
		method private write_statement statement =
			Buffer.add_string buffer (indentation ^ statement ^ ";\n")
		(**
			Build file header (<?php, namespace and file doc block)
		*)
		method private write_header =
			self#indent 0;
			self#write_line "<?php";
			let namespace = wrapper#get_namespace in
			if List.length namespace > 0 then
				self#write_line ("namespace " ^ (String.concat "\\" namespace) ^ ";\n");
			self#write_use
		(**
			Build "use" statements
		*)
		method private write_use =
			self#indent 0;
			let write alias type_path =
				if get_type_name type_path = alias then
					self#write_statement ("use " ^ (get_full_type_name type_path))
				else
					let full_name = get_full_type_name type_path in
					self#write_statement ("use " ^ full_name ^ " as " ^ alias)
			in
			Hashtbl.iter write use_table
		(**
			Generates PHP docblock to output buffer.
		*)
		method private write_doc doc_block =
			match doc_block with
				| DocVar (type_name, None) -> self#write_line ("/** @var " ^ type_name ^ " */")
				| DocVar (type_name, Some doc) ->
					self#write_line "/**";
					self#write_line (" * @var " ^ type_name);
					self#write_doc_description doc;
					self#write_line " */"
				| DocClass doc ->
					(match doc with
						| None -> ()
						| Some txt ->
							self#write_line "/**";
							self#write_doc_description txt;
							self#write_line " */"
					)
				| DocMethod (args, return, doc) ->
					self#write_method_docblock args return doc
		(**
			Writes description section of docblocks
		*)
		method write_doc_description (doc:string) =
			let lines = Str.split (Str.regexp "\n") (String.trim doc)
			and write_line line =
				let trimmed = String.trim line in
				if String.length trimmed > 0 then (
					if String.get trimmed 0 = '*' then
						self#write_line (" " ^ trimmed)
					else
						self#write_line (" * " ^ trimmed)
				)
			in
			List.iter write_line lines
		(**
			Generates docblock for a method and writes it to ourput buffer
		*)
		method write_method_docblock args return_type doc =
			self#write_line "/**";
			(match doc with
				| None -> ()
				| Some txt ->
					self#write_doc_description txt;
					self#write_line " * "
			);
			let write_arg arg =
				match arg with
					| (arg_name, is_optional, arg_type) ->
						self#write_line (" * @param $" ^ arg_name ^ " " ^ (self#use_t arg_type))
			in
			List.iter write_arg args;
			if List.length args > 0 then self#write_line " * ";
			self#write_line (" * @return " ^ (self#use_t return_type));
			self#write_line " */"
		(**
			Writes expression to output buffer
		*)
		method private write_expr (expr:texpr) =
			(match expr.eexpr with
				| TConst const -> self#write_expr_const const
				(* | TLocal of tvar *)
				| TArray (target, index) -> self#write_expr_array_access target index
				(* | TBinop of Ast.binop * texpr * texpr *)
				(* | TField of texpr * tfield_access *)
				(* | TTypeExpr of module_type *)
				(* | TParenthesis of texpr *)

				(* | TObjectDecl of (string * texpr) list *)
				| TArrayDecl exprs -> self#write_expr_array_decl exprs
				(* | TCall of texpr * texpr list *)
				(* | TNew of tclass * tparams * texpr list *)
				(* | TUnop of Ast.unop * Ast.unop_flag * texpr *)
				(* | TFunction of tfunc *)
				(* | TVar of tvar * texpr option *)
				(* | TBlock of texpr list *)
				(* | TFor of tvar * texpr * texpr *)
				(* | TIf of texpr * texpr * texpr option *)
				(* | TWhile of texpr * texpr * Ast.while_flag *)
				(* | TSwitch of texpr * (texpr list * texpr) list * texpr option *)
				(* | TTry of texpr * (tvar * texpr) list *)
				(* | TReturn of texpr option *)
				(* | TBreak *)
				(* | TContinue *)
				(* | TThrow of texpr *)
				(* | TCast of texpr * module_type option *)
				(* | TMeta of metadata_entry * texpr *)
				(* | TEnumParameter of texpr * tenum_field * int *)
				| _ -> ()
			);
		(**
			Writes special method which allows other types to call protected methods of this type.
		*)
		method private write_hx_call_protected =
			self#write_empty_lines;
			self#indent 1;
			self#write_line "/**";
			self#write_line " * @internal";
			self#write_line " * @access protected";
			self#write_line " */";
			self#write_line "public function __hx__call_protected ($method, ...$args)";
			self#write_line "{";
			self#indent_more;
			self#write_line "if (isset($this)) {";
			self#indent_more;
			self#write_line "return call_user_func_array([$this, $method], $args);";
			self#indent_less;
			self#write_line "} else {";
			self#indent_more;
			self#write_line "return call_user_func_array([__CLASS__, $method], $args);";
			self#indent_less;
			self#write_line "}";
			self#indent 1;
			self#write_line "}"
		(**
			Writes special method which allows other types to read protected vars of this type.
		*)
		method private write_hx_get_protected =
			self#write_empty_lines;
			self#indent 1;
			self#write_line "/**";
			self#write_line " * @internal";
			self#write_line " * @access protected";
			self#write_line " */";
			self#write_line "public function __hx__get_protected ($property)";
			self#write_line "{";
			self#indent_more;
			self#write_line "if (isset($this)) {";
			self#indent_more;
			self#write_line "return $this->$property;";
			self#indent_less;
			self#write_line "} else {";
			self#indent_more;
			self#write_line "return static::$$property;";
			self#indent_less;
			self#write_line "}";
			self#indent 1;
			self#write_line "}"
		(**
			Writes special method which allows other types to write protected vars of this type.
		*)
		method private write_hx_set_protected =
			self#write_empty_lines;
			self#indent 1;
			self#write_line "/**";
			self#write_line " * @internal";
			self#write_line " * @access protected";
			self#write_line " */";
			self#write_line "public function __hx__set_protected ($property, $value)";
			self#write_line "{";
			self#indent_more;
			self#write_line "if (isset($this)) {";
			self#indent_more;
			self#write_line "return $this->$property = $value;";
			self#indent_less;
			self#write_line "} else {";
			self#indent_more;
			self#write_line "return static::$$property = $value;";
			self#indent_less;
			self#write_line "}";
			self#indent 1;
			self#write_line "}"
		(**
			Writes TConst to output buffer
		*)
		method private write_expr_const const =
			match const with
				| TInt value -> self#write (Int32.to_string value)
				| TFloat str -> self#write str
				| TString str -> self#write ("\"" ^ (String.escaped str) ^ "\"")
				| TBool value -> self#write (if value then "true" else "false")
				| TNull -> self#write "null"
				| TThis -> self#write "$this->"
				| TSuper -> self#write "parent::"
		(**
			Writes TArrayDecl to output buffer
		*)
		method private write_expr_array_decl exprs =
			self#write "[\n";
			self#indent_more;
			List.iter
				(fun expr ->
					self#write_indentation;
					self#write_expr expr;
					self#write ",\n"
				)
				exprs;
			self#indent_less;
			self#write_indentation;
			self#write "]"
		(**
			Writes TArray to output buffer
		*)
		method private write_expr_array_access target index =
			self#write_expr target;
			self#write "[";
			self#write_expr index;
			self#write "]"
		(**
			Writes TFunction to output buffer
		*)
		method private write_expr_function ?name func =
			let write_arg arg =
				match arg with
					| ({ v_name = arg_name }, None) -> self#write ("$" ^ arg_name)
					| ({ v_name = arg_name }, Some const) ->
						self#write ("$" ^ arg_name ^ " = ");
						self#write_expr_const const
			in
			let rec write_args args =
				match args with
					| [] -> ()
					| [arg] -> write_arg arg
					| arg :: args ->
						write_arg arg;
						self#write ", ";
						write_args args
			in
			let str_name = match name with None -> "" | Some str -> str ^ " " in
			self#write ("function " ^ str_name ^ "(");
			write_args func.tf_args;
			self#write ")";
			(* Closures don't have names. Bracket on same line for closures *)
			if str_name = "" then
				self#write " "
			(* Only methods can be named functions. We want bracket on new line for methods. *)
			else begin
				self#indent 1;
				self#write "\n";
				self#write_indentation;
			end;
			self#write "{\n";
			self#indent_more;
			self#write_expr func.tf_expr;
			self#indent_less;
			self#write_line "}"
	end

(**
	Builds class contents
*)
class class_builder (cls:tclass) =
	object (self)
		inherit type_builder (get_wrapper (TClassDecl cls))
		(**
			Writes type declaration line to output buffer.
			E.g. "class SomeClass extends Another implements IFace"
		*)
		method private write_declaration =
			self#write_doc (DocClass cls.cl_doc);
			self#write (if cls.cl_interface then "interface " else "class ");
			self#write self#get_name;
			(
				match cls.cl_super with
					| None -> ();
					| Some (super_class, _) ->
						let super_name = self#use super_class.cl_path in
						self#write (" extends " ^ super_name)
			);
			if List.length cls.cl_implements > 0 then begin
				self#write (if cls.cl_interface then " extends " else " implements ");
				let use_interface iface =
					match iface with
						| (i, _) -> self#use i.cl_path
				in
				let interfaces = List.map use_interface cls.cl_implements in
				self#write (String.concat ", " interfaces);
			end;
			self#write "\n"
		(**
			Writes type body to output buffer.
			E.g. for "class SomeClass { <BODY> }" writes <BODY> part.
		*)
		method private write_body =
			let write_if_method is_static _ field =
				match field.cf_kind with
					| Var _ -> ()
					| Method _ -> self#write_field is_static field
			and write_if_var is_static _ field =
				match field.cf_kind with
					| Var _ -> self#write_field is_static field
					| Method _ -> ()
			in
		 	if not cls.cl_interface then begin
		 		(* Statc vars *)
				PMap.iter (write_if_var true) cls.cl_statics;
				self#write_empty_lines;
				(* instance vars *)
				PMap.iter (write_if_var false) cls.cl_fields
			end;
			(* Statc methods *)
			PMap.iter (write_if_method true) cls.cl_statics;
			(* Constructor *)
			(match cls.cl_constructor with None -> () | Some field -> self#write_field false field);
			(* Instance methods *)
			PMap.iter (write_if_method false) cls.cl_fields;
			if wrapper#allows_private_calls then self#write_hx_call_protected;
			if wrapper#allows_private_vars_access then begin
				self#write_hx_get_protected;
				self#write_hx_set_protected
			end
		(**
			Writes single field to output buffer
		*)
		method private write_field is_static field =
			match (field.cf_kind) with
				| Var _ -> self#write_var field is_static
				| Method MethNormal -> self#write_method field is_static
				| Method MethInline -> self#write_method field is_static
				| Method MethDynamic -> self#write_method field is_static
				| Method MethMacro -> ()
		(**
			Writes var-field to output buffer
		*)
		method private write_var field is_static =
			self#indent 1;
			self#write_doc (DocVar (self#use_t field.cf_type, field.cf_doc));
			self#write_indentation;
			if is_static then self#write "static ";
			let visibility = get_visibility field.cf_meta in
			self#write (visibility ^ " $" ^ field.cf_name);
			match field.cf_expr with
				| None -> self#write ";\n"
				| Some expr ->
					self#write " = ";
					self#write_expr expr;
					self#write ";\n"
		(**
			Writes method to output buffer
		*)
		method private write_method field is_static =
			self#write_empty_lines;
			self#indent 1;
			let (args, return_type) =
				(match follow field.cf_type with
					| TFun (args, return_type) -> (args, return_type)
					| _ -> failwith ("Invalid signature of method " ^ field.cf_name)
				)
			in
			self#write_doc (DocMethod (args, return_type, field.cf_doc));
			self#write_indentation;
			if is_static then self#write "static ";
			self#write ((get_visibility field.cf_meta) ^ " ");
			match field.cf_expr with
				| None ->
					let write_arg (arg_name, optional, _) =
						self#write ("$" ^ arg_name ^ (if optional then " = null" else ""))
					in
					let rec write_args args =
						match args with
							| [] -> ()
							| [arg] -> write_arg arg
							| arg :: args ->
								write_arg arg;
								self#write ", ";
								write_args args
					in
					self#write (field.cf_name ^ " (");
					write_args args;
					self#write ")";
					self#write " ;\n"
				| Some { eexpr = TFunction fn } ->
					let name = if field.cf_name = "new" then "__construct" else field.cf_name in
					self#write_expr_function ~name:name fn
				| _ -> failwith ("invalid expression for method " ^ field.cf_name)
	end

(**
	Handles generation process
*)
class generator (com:context) =
	object (self)
		val mutable build_dir = ""
		val root_dir = com.file
		(**
			Perform required action before actual php files generation
		*)
		method initialize =
			self#create_output_dirs;
		(**
			Generates php file for specified type
		*)
		method generate (builder:type_builder) =
			let namespace = builder#get_namespace
			and name = builder#get_name in
			let filename = (create_dir_recursive (build_dir :: namespace)) ^ "/" ^ name ^ ".php" in
			let channel = open_out filename in
			output_string channel builder#get_contents;
			close_out channel
		(**
			Create necessary directories  before processing types
		*)
		method private create_output_dirs =
			let lib_path =
				match com.php_lib with
					| None -> ["lib"];
					| Some path -> (Str.split (Str.regexp "/")  path)
			in
			let build_path = (root_dir :: lib_path) in
			build_dir <- create_dir_recursive build_path
	end

(**
	Entry point to Genphp7
*)
let generate (com:context) =
	let gen = new generator com in
	gen#initialize;
	let generate com_type =
		let wrapper = get_wrapper com_type in
		if wrapper#needs_generation then
			match com_type with
				| TClassDecl cls -> gen#generate (new class_builder cls);
				| TEnumDecl tenum -> ();
				| TTypeDecl typedef -> ();
				| TAbstractDecl abstr -> ()
	in
	List.iter generate com.types