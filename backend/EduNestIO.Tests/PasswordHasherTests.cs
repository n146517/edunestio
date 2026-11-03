using EduNestIO.Common.Security;

namespace EduNestIO.Tests;

/// <summary>
/// Unit tests for the PBKDF2 password hasher. These run with no database.
/// </summary>
public class PasswordHasherTests
{
    [Fact]
    public void Hash_then_Verify_succeeds_for_correct_password()
    {
        var (hash, salt) = PasswordHasher.Hash("Str0ng!Passw0rd");
        Assert.True(PasswordHasher.Verify("Str0ng!Passw0rd", hash, salt));
    }

    [Fact]
    public void Verify_fails_for_wrong_password()
    {
        var (hash, salt) = PasswordHasher.Hash("Str0ng!Passw0rd");
        Assert.False(PasswordHasher.Verify("wrong-password", hash, salt));
    }

    [Fact]
    public void Each_hash_uses_a_unique_salt()
    {
        var (h1, s1) = PasswordHasher.Hash("same");
        var (h2, s2) = PasswordHasher.Hash("same");
        Assert.NotEqual(s1, s2);
        Assert.NotEqual(h1, h2); // different salt -> different derived key
    }

    [Fact]
    public void Session_tokens_are_unique_and_url_safe()
    {
        var a = PasswordHasher.NewSessionToken();
        var b = PasswordHasher.NewSessionToken();
        Assert.NotEqual(a, b);
        Assert.DoesNotContain('+', a);
        Assert.DoesNotContain('/', a);
        Assert.DoesNotContain('=', a);
    }
}
