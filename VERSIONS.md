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

## 0.3.2

- fix error in tls options passing and docs for daemon.

## Future Versions:

- upgrade to Phoenix PubSub 2.0.0
