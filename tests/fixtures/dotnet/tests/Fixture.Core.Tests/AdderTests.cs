using Xunit;

namespace Fixture.Core.Tests;

public class AdderTests
{
    [Fact]
    public void AddsTwoNumbers() => Assert.Equal(5, Adder.Add(2, 3));
}
