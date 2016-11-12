/*
 * Copyright (C)2005-2016 Haxe Foundation
 *
 * Permission is hereby granted, free of charge, to any person obtaining a
 * copy of this software and associated documentation files (the "Software"),
 * to deal in the Software without restriction, including without limitation
 * the rights to use, copy, modify, merge, publish, distribute, sublicense,
 * and/or sell copies of the Software, and to permit persons to whom the
 * Software is furnished to do so, subject to the following conditions:
 *
 * The above copyright notice and this permission notice shall be included in
 * all copies or substantial portions of the Software.
 *
 * THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
 * IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
 * FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
 * AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
 * LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING
 * FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER
 * DEALINGS IN THE SOFTWARE.
 */

import php7.Boot;
import php7.Syntax;
import php7.Closure;
import haxe.Constraints;

using php7.Global;

@:coreApi class Reflect {

	public static function hasField( o : Dynamic, field : String ) : Bool {
		return o.is_object() && o.property_exists(field);
	}

	public static function field( o : Dynamic, field : String ) : Dynamic {
		if (!o.is_object()) return null;

		if (o.property_exists(field)) {
			return Syntax.getField(o, field);
		}
		if (o.method_exists(field)) {
			return Boot.closure(o, field);
		}

		if (Syntax.instanceof(o, cast Boot.getHxClass())) {
			if (Global.property_exists(o.phpClassName, field)) {
				return Syntax.getField(o, field);
			}
			if (Global.method_exists(o.phpClassName, field)) {
				return Boot.closure(o.phpClassName, field);
			}
		}

		return null;
	}

	public static function setField( o : Dynamic, field : String, value : Dynamic ) : Void {
		Syntax.setField(o, field, value);
	}

	public static function getProperty( o : Dynamic, field : String ) : Dynamic {
		if (o.is_object()) {
			if (Boot.hasGetter(Global.get_class(o), field)) {
				return Syntax.call(o, 'get_$field');
			} else if (Global.method_exists(o, field)) {
				return Boot.closure(o, field);
			} else {
				return Syntax.getField(o, field);
			}
		}
		if (o.is_string() && field == 'length') {
			return Global.strlen(o);
		}
		return null;
	}

	public static function setProperty( o : Dynamic, field : String, value : Dynamic ) : Void {
		if (o.is_object()) {
			if (Boot.hasSetter(Global.get_class(o), field)) {
				Syntax.call(o, 'set_$field', value);
			} else {
				Syntax.setField(o, field, value);
			}
		}
	}

	public static function callMethod( o : Dynamic, func : Function, args : Array<Dynamic> ) : Dynamic {
		if (Syntax.instanceof(func, Closure)) {
			if (o != null) {
				func = cast cast(func, Closure).bindTo(o);
			}
			return Global.call_user_func_array(func, @:privateAccess args.arr);
		} else {
			return Boot.castClosure(func).callWith(o, @:privateAccess args.arr);
		}
	}

	public static function fields( o : Dynamic ) : Array<String> {
		if (Global.is_object(o)) {
			return @:privateAccess Array.wrap(Global.get_object_vars(o).array_keys());
		}
		return [];
	}

	public static function isFunction( f : Dynamic ) : Bool {
		if (Syntax.instanceof(f, Closure)) {
			return true;
		} else {
			return Syntax.instanceof(f, cast Boot.closureHxClass());
		}
	}

	public static function compare<T>( a : T, b : T ) : Int {
		if (a == b) return 0;
		if (Global.is_string(a)){
			return Global.strcmp(cast a, cast b);
		} else {
			return ((cast a) > (cast b) ? 1 : -1);
		}
	}

	public static function compareMethods( f1 : Dynamic, f2 : Dynamic ) : Bool {
		var hxClosure : Class<Dynamic> = cast Boot.closureHxClass();
		if (Syntax.instanceof(f1, hxClosure) && Syntax.instanceof(f2, hxClosure)) {
			return f1.equals(f2);
		} else {
			return f1 == f2;
		}
	}

	public static function isObject( v : Dynamic ) : Bool {
		if (Boot.isEnumValue(v)) {
			return false;
		} else {
			return v.is_object() || v.is_string();
		}
	}

	public static inline function isEnumValue( v : Dynamic ) : Bool {
		return Boot.isEnumValue(v);
	}

	public static function deleteField( o : Dynamic, field : String ) : Bool {
		if (hasField(o, field)) {
			untyped Global.unset(Syntax.getField(o, field));
			return true;
		} else {
			return false;
		}
	}

	public static function copy<T>( o : T ) : T {
		if (Global.is_object(o)) {
			var fields = Global.get_object_vars(cast o);
			var hxAnon = Boot.getHxAnon().phpClassName;
			return Syntax.construct(hxAnon, fields);
		} else {
			return null;
		}
	}

	@:overload(function( f : Array<Dynamic> -> Void ) : Dynamic {})
	public static function makeVarArgs( f : Array<Dynamic> -> Dynamic ) : Dynamic {
		return function () {
			return Global.call_user_func_array(f, Global.func_get_args());
		}
	}


}
