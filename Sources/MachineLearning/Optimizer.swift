// Copyright 2018 The TensorFlow Authors. All Rights Reserved.
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//     http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.

import TensorFlow

public protocol Optimizer : AnyObject {
    associatedtype Model: Layer
    associatedtype Scalar: FloatingPoint
    var learningRate: Scalar { get }
    func fit(_ model: inout Model, along gradient: Model.CotangentVector)
}

public class SGDOptimizer<Model : Layer, Scalar: BinaryFloatingPoint & TensorFlowScalar>: Optimizer
    where Model.AllDifferentiableVariables : KeyPathIterable & VectorNumeric,
          Model.AllDifferentiableVariables == Model.CotangentVector,
          Model.AllDifferentiableVariables.Scalar == Scalar
{
    public let learningRate: Scalar
    public let momentum: Scalar
    public let decay: Scalar
    public let nesterov: Bool

    public init(
        learningRate: Scalar = 0.01,
        momentum: Scalar = 0,
        decay: Scalar = 0,
        nesterov: Bool = false
    ) {
        precondition(learningRate >= 0, "Learning rate must be non-negative")
        precondition(momentum >= 0, "Momentum must be non-negative")
        precondition(decay >= 0, "Weight decay must be non-negative")

        self.learningRate = learningRate
        self.momentum = momentum
        self.decay = decay
        self.nesterov = nesterov
    }

    var velocity = Model.AllDifferentiableVariables.zero

    public func fit(_ model: inout Model, along gradients: Model.CotangentVector) {
        for kp in model.allDifferentiableVariables
                       .recursivelyAllWritableKeyPaths(to: Tensor<Scalar>.self) {
            velocity[keyPath: kp] =
                momentum * velocity[keyPath: kp] - learningRate * gradients[keyPath: kp]
            if nesterov {
                model.allDifferentiableVariables[keyPath: kp] += velocity[keyPath: kp]
            } else {
                model.allDifferentiableVariables[keyPath: kp] =
                    model.allDifferentiableVariables[keyPath: kp] +
                    momentum * velocity[keyPath: kp] -
                    learningRate * gradients[keyPath: kp]
            }
        }
    }
}

public class Adam<Model : Layer, Scalar: BinaryFloatingPoint & TensorFlowScalar>: Optimizer
    where Model.AllDifferentiableVariables : KeyPathIterable & VectorNumeric,
          Model.AllDifferentiableVariables == Model.CotangentVector,
          Model.AllDifferentiableVariables.Scalar == Scalar
{
    public let learningRate: Scalar
    public var beta1: Scalar
    public var beta2: Scalar
    public let epsilon: Scalar
    public let decay: Scalar

    public init(
        learningRate: Scalar = 1e-3,
        beta1: Scalar = 0.9,
        beta2: Scalar = 0.999,
        epsilon: Scalar = 1e-8,
        decay: Scalar = 0
    ) {
        precondition(learningRate >= 0, "Learning rate must be non-negative")
        precondition(0 <= beta1 && beta1 <= 1, "Beta parameter must be between 0 and 1")
        precondition(0 <= beta2 && beta2 <= 1, "Beta parameter must be between 0 and 1")
        precondition(decay >= 0, "Weight decay must be non-negative")

        self.learningRate = learningRate
        self.beta1 = beta1
        self.beta2 = beta2
        self.epsilon = epsilon
        self.decay = decay
    }

    var step: Scalar = 0
    var firstMoments = Model.AllDifferentiableVariables.zero
    var secondMoments = Model.AllDifferentiableVariables.zero

    public func fit(_ model: inout Model, along gradients: Model.CotangentVector) {
        for kp in model.allDifferentiableVariables
                       .recursivelyAllWritableKeyPaths(to: Tensor<Scalar>.self) {
            firstMoments[keyPath: kp] =
                firstMoments[keyPath: kp] * beta1 + (1 - beta1) * gradients[keyPath: kp]
            secondMoments[keyPath: kp] =
                firstMoments[keyPath: kp] * beta2 + (1 - beta2) *
                gradients[keyPath: kp] * gradients[keyPath: kp]

            let denominator = sqrt(secondMoments[keyPath: kp]) + epsilon
            step += 1
            let biasCorrection1 = 1 - pow(beta1, step)
            let biasCorrection2 = 1 - pow(beta2, step)
            let stepSize = learningRate * sqrt(biasCorrection2) / biasCorrection1
            model.allDifferentiableVariables[keyPath: kp] -=
                stepSize * firstMoments[keyPath: kp] / denominator
        }
    }
}

public class RiemannSGD<Model: Layer, Scalar: FloatingPoint>: Optimizer
    where Model.CotangentVector : VectorNumeric, Model.CotangentVector.Scalar == Scalar {
    public var learningRate: Scalar

    public init(learningRate: Scalar) {
        self.learningRate = learningRate
    }

    public func fit(_ model: inout Model, along gradient: Model.CotangentVector) {
        model = model.moved(along: model.tangentVector(from: Model.CotangentVector.zero - gradient))
    }
}
