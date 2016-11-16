package php7.db;

import php7.*;
import haxe.extern.EitherType;
import haxe.Constraints;

/**
    @see http://php.net/manual/en/ref.sqlite.php
**/
@:native('SQLiteDatabase')
extern class SQLiteDatabase {
    @:final function new( filename:String, ?mode:Int, ?error_message:Ref<String> ) : Void;
    function query( query:String, ?result_type:Int, error_msg:Ref<String> ) : EitherType<Bool,SQLiteResult>;
    function queryExec( query:String, ?error_msg:Ref<String> ) : Bool;
    function arrayQuery( query:String, ?result_type:Int, decode_binary:Bool = true) : NativeArray;
    function singleQuery( query:String, ?first_row_only:Bool, ?decode_binary:Bool ) : NativeArray;
    // function unbufferedQuery( query:String, ?result_type:Int, ?error_msg:Ref<String> ) : SQLiteUnbuffered;
    function lastInsertRowid() : Int;
    function changes() : Int;
    function createAggregate( function_name:String, step_func:Function, finalize_func:Function, num_args:Int = -1 ) : Void;
    function createFunction( function_name:String, callback:Function, num_args:Int = -1 ) : Void;
    function busyTimeout( milliseconds:Int ) : Void;
    function lastError() : Int;
    function fetchColumnTypes( table_name:String, ?result_type:Int ) : NativeArray;
}