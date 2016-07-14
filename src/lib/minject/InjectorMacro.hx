// See the file "LICENSE" for the full license governing this code

package minject;

#if macro
import haxe.macro.Context;
import haxe.macro.Compiler;
import haxe.macro.Expr;
import haxe.macro.Type;
import tink.SyntaxHub;

using tink.MacroApi;
using haxe.macro.Tools;
using Lambda;

class InjectorMacro
{
	static var keptTypes = new Map<String, Bool>();
	
	public static function use() {
		SyntaxHub.classLevel.after(
			function(_) return true,
			function(c:ClassBuilder) {
				processInst(c);
				return false; // it doesn't modify the fields
			}
		);
	}
	/**
		Called by the injector at macro time to tell the compiler which
		constructors should be kept (as they are mapped in for instantiation
		by the injector with Type.createInstance)
	**/
	public static function keep(expr:Expr)
	{
		switch (Context.typeof(expr))
		{
			case TType(t, _):
				var type = t.get();

				var name = type.name;
				name = name.substring(6, name.length - 1);

				if (keptTypes.exists(name)) return;
				keptTypes.set(name, true);

				var module = Context.getModule(type.module);

				for (moduleType in module) switch (moduleType)
				{
					case TInst(t, _):
						var theClass = t.get();
						var className = theClass.pack.concat([theClass.name]).join('.');
						if (className != name) continue;
						if (theClass.constructor != null)
							theClass.constructor.get().meta.add(':keep', [], Context.currentPos());
					case _:
				}
			case _:
		}
	}

	/**
		Returns a string representing the type for the supplied value

		- if expr is a type (String, foo.Bar) result is full type path
		- anything else is passed to `Injector.getValueType` which will attempt to determine a
		  runtime type name.
	**/
	public static function getExprType(expr:Expr):Expr
	{
		switch (expr.expr)
		{
			case EConst(CString(_)): return expr;
			default:
		}
		switch (Context.typeof(expr))
		{
			case TType(_, _):
				var expr = expr.toString();
				try
				{
					var type = getType(Context.getType(expr));
					var index = type.indexOf("<");
					var typeWithoutParams = (index>-1) ? type.substr(0, index) : type;
					return macro $v{typeWithoutParams};
				}
				catch (e:Dynamic) {}
			default:
		}
		return expr;
	}

	public static function getValueId(expr:Expr):Expr
	{
		var type = Context.typeof(expr).toString();
		return macro $v{type};
	}

	public static function getValueType(expr:Expr):ComplexType
	{
		switch (expr.expr)
		{
			case EConst(CString(type)):
				return getComplexType(type);
			default:
		}
		switch (Context.typeof(expr))
		{
			case TType(_, _):
				return getComplexType(expr.toString());
			default:
		}
		return null;
	}

	static function getComplexType(type:String):ComplexType
	{
		return switch (Context.parse('(null:Null<$type>)', Context.currentPos()))
		{
			case macro (null:$type): type;
			default: null;
		}
	}

	static function getType(type:Type):String
	{
		return followType(type).toString();
	}

	/**
		Follow TType references, but not if they point to TAnonymous
	**/
	static function followType(type:Type):Type
	{
		switch (type)
		{
			case TType(t, params):
				if (Std.string(t) == 'Null')
					return followType(params[0]);
				return switch (t.get().type)
				{
					case TAnonymous(_): type;
					case ref: followType(ref);
				}
			default:
				return type;
		}
	}

	// static function processTypes(types:Array<Type>):Void
	// {
	// 	for (type in types) switch (type)
	// 	{
	// 		case TInst(t, _): processInst(t);
	// 		default:
	// 	}
	// }

	static function processInst(c:ClassBuilder):Void
	{
		var ref = c.target;
		
		// add meta to interfaces, there's no otherway of telling at runtime!
		if (ref.isInterface && !ref.meta.has('interface')) ref.meta.add("interface", [], ref.pos);
		
		var infos = [];
		var keep = new Map<String, Bool>();

		// process constructor
		if (c.hasConstructor()) processField(c.getConstructor().toHaxe(), infos, keep);

		// process fields
		for (field in c) processField(field, infos, keep);

		// keep additional injectee fields (setters)
		for (field in c)
			if (keep.exists(field.name))
				field.addMeta(':keep');

		// add rtti to type
		var rtti = infos.map(function (rtti) return macro $v{rtti});
		if (rtti.length > 0) ref.meta.add('rtti', rtti, ref.pos);
	}

	static function processField(field:Member, rttis:Array<Array<String>>, keep:Map<String, Bool>):Void
	{
		if (!field.isPublic) return;

		// find minject metadata
		var inject = field.extractMeta('inject').orNull();
		var post = field.extractMeta('post').orNull();

		// only process public fields with minject metadata
		if (inject == null && post == null) return;

		// keep injected fields
		field.addMeta(':keep');
		
		// extract injection names from metadata
		var names = [];
		if (inject != null)
		{
			names = inject.params;
		}

		var rtti = [field.name];
		rttis.push(rtti);

		switch (field.kind)
		{
			case FVar(t, e) | FProp(_, _, t, e):
				keep.set('set_' + field.name, true);
				rtti.push(getType(t.toType()));
				if (names.length > 0) rtti.push(names[0].getValue());
				else rtti.push('');
			case FFun(fun):
						if (post != null)
						{
							var order = post.params.length > 0 ? post.params[0].getValue() + 1 : 1;
							rtti.push(""+order);
						}
						else
						{
							rtti.push("");
						}
						
						var args = fun.args;
						for (i in 0...args.length)
						{
							var arg = args[i];
							var type = getType(arg.type.toType());

							if (!arg.opt && type == 'Dynamic')
							{
								Context.error('Error in method definition of injectee. Required ' +
									'parameters can\'t have type "Dynamic"', field.pos);
							}

							rtti.push(type);
							rtti.push(names[i] == null ? '' : names[i].getValue());
							rtti.push(arg.opt ? 'o' : '');
						}
		}
	}
}
#end
