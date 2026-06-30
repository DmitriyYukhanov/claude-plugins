namespace Demo;

public interface IProvider
{
    string WrapGreeting(string greeting);
}

public class DefaultProvider : IProvider
{
    public string WrapGreeting(string greeting) => $"[demo] {greeting}";
}
