//
//  PromiseSource.swift
//  Promissum
//
//  Created by Tom Lokhorst on 2014-10-11.
//  Copyright (c) 2014 Tom Lokhorst. All rights reserved.
//

import Foundation

/**
## Creating Promises

A PromiseSource is used to create a Promise that can be resolved or rejected.

Example:

```
let source = PromiseSource<Int, String>()
let promise = source.promise

// Register handlers with Promise
promise
  .then { value in
    print("The value is: \(value)")
  }
  .trap { error in
    print("The error is: \(error)")
  }

// Resolve the source (will call the Promise handler)
source.resolve(42)
```

Once a PromiseSource is Resolved or Rejected it cannot be changed anymore.
All subsequent calls to `resolve` and `reject` are ignored.

## When to use
A PromiseSource is needed when transforming an asynchronous operation into a Promise.

Example:
```
func someOperationPromise() -> Promise<String, ErrorType> {
  let source = PromiseSource<String, ErrorType>()

  someOperation(callback: { (error, value) in
    if let error = error {
      source.reject(error)
    }
    if let value = value {
      source.resolve(value)
    }
  })

  return promise
}
```

## Memory management
Make sure, when creating a PromiseSource, that someone retains a reference to the source.

In the example above the `someOperation` retains the callback.
But in some cases, often when using weak delegates, the callback is not retained.
In that case, you must manually retain the PromiseSource, or the Promise will never complete.

Note that `PromiseSource.deinit` by default will log a warning when an unresolved PromiseSource is deallocated.

*/
public class PromiseSource<Value, Error> {
  typealias ResultHandler = (Result<Value, Error>) -> Void

  private var handlers: [(Result<Value, Error>) -> Void] = []
  internal let dispatchMethod: DispatchMethod

  /// The current state of the PromiseSource
  private(set) public var state: State<Value, Error>

  /// Print a warning on deinit of an unresolved PromiseSource
  public var warnUnresolvedDeinit: Bool

  // MARK: Initializers & deinit

  internal convenience init(value: Value) {
    self.init(state: .resolved(value), dispatch: .unspecified, warnUnresolvedDeinit: false)
  }

  internal convenience init(error: Error) {
    self.init(state: .rejected(error), dispatch: .unspecified, warnUnresolvedDeinit: false)
  }

  /// Initialize a new Unresolved PromiseSource
  ///
  /// - parameter warnUnresolvedDeinit: Print a warning on deinit of an unresolved PromiseSource
  public convenience init(dispatch: DispatchMethod = .unspecified, warnUnresolvedDeinit: Bool = true) {
    self.init(state: .unresolved, dispatch: dispatch, warnUnresolvedDeinit: warnUnresolvedDeinit)
  }

  internal init(state: State<Value, Error>, dispatch: DispatchMethod, warnUnresolvedDeinit: Bool) {
    self.state = state
    self.dispatchMethod = dispatch
    self.warnUnresolvedDeinit = warnUnresolvedDeinit
  }

  deinit {
    if warnUnresolvedDeinit {
      switch state {
      case .unresolved:
        print("PromiseSource.deinit: WARNING: Unresolved PromiseSource deallocated, maybe retain this object?")
      default:
        break
      }
    }
  }


  // MARK: Computed properties

  /// Promise related to this PromiseSource
  public var promise: Promise<Value, Error> {
    return Promise(source: self)
  }


  // MARK: Resolve / reject

  /// Resolve an Unresolved PromiseSource with supplied value.
  ///
  /// When called on a PromiseSource that is already Resolved or Rejected, the call is ignored.
  public func resolve(_ value: Value) {

    resolveResult(.Value(value))
  }


  /// Reject an Unresolved PromiseSource with supplied error.
  ///
  /// When called on a PromiseSource that is already Resolved or Rejected, the call is ignored.
  public func reject(_ error: Error) {

    resolveResult(.Error(error))
  }

  internal func resolveResult(_ result: Result<Value, Error>) {

    switch state {
    case .unresolved:
      state = result.state

      executeResultHandlers(result)
    default:
      break
    }
  }

  private func executeResultHandlers(_ result: Result<Value, Error>) {

    // Call all previously scheduled handlers
    callHandlers(result, handlers: handlers, dispatchMethod: dispatchMethod)

    // Cleanup
    handlers = []
  }

  // MARK: Adding result handlers

  internal func addOrCallResultHandler(_ handler: (Result<Value, Error>) -> Void) {

    switch state {
    case .unresolved:
      // Save handler for later
      handlers.append(handler)

    case .resolved(let value):
      // Value is already available, call handler immediately
      callHandlers(Result.Value(value), handlers: [handler], dispatchMethod: dispatchMethod)

    case .rejected(let error):
      // Error is already available, call handler immediately
      callHandlers(Result.Error(error), handlers: [handler], dispatchMethod: dispatchMethod)
    }
  }
}

internal func callHandlers<T>(_ value: T, handlers: [(T) -> Void], dispatchMethod: DispatchMethod) {

  for handler in handlers {
    switch dispatchMethod {
    case .unspecified:

      if Thread.isMainThread() {
        handler(value)
      }
      else {
        DispatchQueue.main.async {
          handler(value)
        }
      }

    case .synchronous:

      handler(value)

    case let .onQueue(targetQueue):
      let currentQueueLabel: String? = nil // String(validatingUTF8: DISPATCH_CURRENT_QUEUE_LABEL.label)!

      // Assume on correct queue if labels match, but be conservative if label is empty
      let alreadyOnQueue = currentQueueLabel == targetQueue.label

      if alreadyOnQueue {
        handler(value)
      }
      else {
        targetQueue.async {
          handler(value)
        }
      }
    }
  }
}
