import TensorFlow

public protocol  MyEuclideanDifferentiable: EuclideanDifferentiable {
    var differentiableVectorView: TangentVector { get set }
}

public extension MyEuclideanDifferentiable where TangentVector == Self {
    var differentiableVectorView: TangentVector {
        _read { yield self }
        _modify { yield &self }
    }
}

public protocol HasSlowWeights {
    associatedtype Model: Differentiable
    var slowWeights: Model.TangentVector {get set}
}

public class Lookahead<Opt: Optimizer, Model: MyEuclideanDifferentiable & Layer>: Optimizer & HasSlowWeights
    where Opt.Model == Model,
          Model.TangentVector.VectorSpaceScalar == Float,
          Model.TangentVector: KeyPathIterable,
          Opt.Scalar: TensorFlowFloatingPoint  {
    public typealias Model = Model
    public typealias Opt = Opt
    public var optimizer: Opt
    public var learningRate: Opt.Scalar {
        willSet { optimizer.learningRate = Opt.Scalar(newValue) }
    }
    public var step: Int = 0
    public var outerStep: Int = 6
    public var slowWeights: Model.TangentVector
    
    public init(for model: __shared Model, optimizer: Opt, outerStep: Int = 6){
        self.slowWeights = model.differentiableVectorView
        self.optimizer = optimizer
        self.learningRate = optimizer.learningRate
        self.outerStep = outerStep
    }
    
    public func update(_ model: inout Model, along direction: Model.TangentVector) {
        step += 1
        optimizer.update(&model, along: direction)
        if step % outerStep == 0 {
            var updateWeights = model.differentiableVectorView
            for kp in updateWeights.recursivelyAllWritableKeyPaths(to: Tensor<Float>.self) {
                updateWeights[keyPath: kp] = (updateWeights[keyPath: kp] + slowWeights[keyPath: kp]) / Float(2)
            }
            model.differentiableVectorView = updateWeights
            slowWeights = updateWeights
        }
    }
}

public class LookaheadFurther<Opt: Optimizer, Model: MyEuclideanDifferentiable & Layer>: Lookahead<Opt, Model>
    where Opt: HasSlowWeights, Opt.Model == Model,
          Model.TangentVector.VectorSpaceScalar == Float,
          Model.TangentVector: KeyPathIterable,
          Opt.Scalar: TensorFlowFloatingPoint  {
    public override var slowWeights: Model.TangentVector {
        willSet { optimizer.slowWeights = newValue }
    }
}
