# Pony Express Versions

## 0.1.0

- basic proof of concept

## 0.2.0

- documentation clarification
- now uses `Erps` package to unify TLS semantics
- automatic TLS test file generation for tests
- Use `Plug.Crypto.non_executable_binary_to_term/2` for translating messages

## 0.2.1

- clean up modules provided for API definition
- update erps dependency

## 0.3.0

- reject the case where the client forgets to specify a topic
- server closes the client immediately if no topic is specified
- allow information packet to exceed the MTU
- allow client connection errors to trigger reconnect attempt

## 0.3.1

- bump dependency to newer version of ERPS

## 0.3.3

- fix error in tls options passing and docs for daemon.

## 0.4.0

- update to use `connection` library
- update to use `transport` library

## 0.4.1

- fix TLS settings bug
- make TLS test actually use TLS
- fix duplicate key error

## 0.4.2

- accept the situation when multiple packets are squished together

## 0.4.3

- upgraded to Phoenix PubSub 2.0.0

## 0.5.0

- integration of `Multiverses`
- change PonyExpress.port to return an ok tuple

## 0.5.1

- improvement of tests and better Multiverses integration

## 0.6.0

- update for use use with Multiverses 0.7.0
