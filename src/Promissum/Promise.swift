//
//  Promise.swift
//  Promissum
//
//  Created by Tom Lokhorst on 2014-10-11.
//  Copyright (c) 2014 Tom Lokhorst. All rights reserved.
//

import Foundation

public let PromissumErrorDomain = "com.nonstrict.Promissum"

public class Promise<T> {
  internal(set) var state: State<T>

  internal init(source: PromiseSource<T>) {
    self.state = State.Unresolved(source)
  }

  public init(value: T) {
    state = State<T>.Resolved(Box(value))
  }

  public init(error: NSError) {
    state = State<T>.Rejected(error)
  }

  public func value() -> T? {
    switch state {
    case State<T>.Resolved(let boxed):
      return boxed.unbox
    default:
      return nil
    }
  }

  public func error() -> NSError? {
    switch state {
    case State<T>.Rejected(let error):
      return error
    default:
      return nil
    }
  }

  public func result() -> Result<T>? {
    switch state {
    case State<T>.Resolved(let boxed):
      return .Value(boxed)
    case State<T>.Rejected(let error):
      return .Error(error)
    default:
      return nil
    }
  }

  public func then(handler: T -> Void) -> Promise<T> {
    addResolvedHandler(handler)

    return self
  }

  public func map<U>(transform: T -> U) -> Promise<U> {
    let source = PromiseSource<U>(
      onThenHandler: { p, thenHandler in
        self.addResolvedHandler({ _ in
          p.addResolvedHandler(thenHandler)
        })
      },
      onCatchHandler: { p, catchHandler in
        self.addErrorHandler({ _ in
          p.addErrorHandler(catchHandler)
        })
      },
      warnUnresolvedDeinit: true)

    let cont: T -> Void = { val in
      var transformed = transform(val)
      source.resolve(transformed)
    }

    addResolvedHandler(cont)
    addErrorHandler(source.reject)

    return source.promise
  }

  public func flatMap<U>(transform: T -> Promise<U>) -> Promise<U> {
    let source = PromiseSource<U>()

    let cont: T -> Void = { val in
      var transformedPromise = transform(val)
      transformedPromise
        .then(source.resolve)
        .catch(source.reject)
    }

    addResolvedHandler(cont)
    addErrorHandler(source.reject)

    return source.promise
  }

  public func mapError(transform: NSError -> T) -> Promise<T> {
    let source = PromiseSource<T>(
      onThenHandler: { p, thenHandler in
        self.addErrorHandler({ _ in
          p.addResolvedHandler(thenHandler)
        })
      },
      onCatchHandler: nil,
      warnUnresolvedDeinit: true)

    let cont: NSError -> Void = { error in
      var transformed = transform(error)
      source.resolve(transformed)
    }

    addErrorHandler(cont)
    addResolvedHandler(source.resolve)

    return source.promise
  }

  public func flatMapError(transform: NSError -> Promise<T>) -> Promise<T> {
    let source = PromiseSource<T>()

    let cont: NSError -> Void = { error in
      var transformedPromise = transform(error)
      transformedPromise
        .then(source.resolve)
        .catch(source.reject)
    }

    addErrorHandler(cont)
    addResolvedHandler(source.resolve)

    return source.promise
  }

  public func catch(handler: NSError -> Void) -> Promise<T> {
    addErrorHandler(handler)

    return self
  }

  public func mapResult(transform: Result<T> -> T) -> Promise<T> {
    let source = PromiseSource<T>()

    let contError: NSError -> Void = { error in
      var transformed = transform(Result.Error(error))
      source.resolve(transformed)
    }

    let contValue: T -> Void = { value in
      var transformed = transform(Result.Value(Box(value)))
      source.resolve(transformed)
    }

    addErrorHandler(contError)
    addResolvedHandler(contValue)

    return source.promise
  }

  public func flatMapResult(transform: Result<T> -> Promise<T>) -> Promise<T> {
    let source = PromiseSource<T>()

    let contError: NSError -> Void = { error in
      var transformedPromise = transform(Result.Error(error))
      transformedPromise
        .then(source.resolve)
        .catch(source.reject)
    }

    let contValue: T -> Void = { value in
      var transformedPromise = transform(Result.Value(Box(value)))
      transformedPromise
        .then(source.resolve)
        .catch(source.reject)
    }

    addErrorHandler(contError)
    addResolvedHandler(contValue)

    return source.promise
  }

  public func finallyResult(handler: Result<T> -> Void) -> Promise<T> {

    let resolvedCont: T -> Void = { val in
      handler(Result.Value(Box(val)))
    }

    let errorCont: NSError -> Void = { error in
      handler(Result.Error(error))
    }

    addResolvedHandler(resolvedCont)
    addErrorHandler(errorCont)

    return self
  }

  public func finally(handler: () -> Void) -> Promise<T> {

    addResolvedHandler({ _ in handler() })
    addErrorHandler({ _ in handler() })

    return self
  }

  private func addResolvedHandler(handler: T -> Void) {

    switch state {
    case let State<T>.Unresolved(source):
      // Save handler for later
      source.addResolvedHander(handler)

    case State<T>.Resolved(let boxed):
      // Value is already available, call handler immediately
      let value = boxed.unbox
      callHandlers(value, [handler])

    case State<T>.Rejected:
      break;
    }
  }

  private func addErrorHandler(handler: NSError -> Void) {

    switch state {
    case let State<T>.Unresolved(source):
      // Save handler for later
      source.addErrorHandler(handler)

    case State<T>.Rejected(let error):
      // Error is already available, call handler immediately
      callHandlers(error, [handler])

    case State<T>.Resolved:
      break;
    }
  }
}
