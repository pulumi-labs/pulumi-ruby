# random-pet

A minimal Pulumi program in Ruby, using the [`random`](https://www.pulumi.com/registry/packages/random/)
provider so it needs no cloud credentials.

```console
$ pulumi stack init dev
$ pulumi install
$ pulumi up
```

It shows the three ways to declare a resource, a component resource, and combining
`Output`s with `Output.all` and `Output.format`.
