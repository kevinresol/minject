package minject;

import minject.point.InjectionPoint;

class InjectorInfo
{
	public var ctor:InjectionPoint;
	public var injectionPoints:Array<InjectionPoint>;

	public function new(ctor:InjectionPoint, injectionPoints:Array<InjectionPoint>)
	{
		this.ctor = ctor;
		this.injectionPoints = injectionPoints;
	}
}