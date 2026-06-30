namespace Demo;

public class Service
{
    private readonly IProvider _provider;

    public Service(IProvider provider) => _provider = provider;

    public string Greet(string name) => _provider.WrapGreeting($"Hello, {name}!");
}
