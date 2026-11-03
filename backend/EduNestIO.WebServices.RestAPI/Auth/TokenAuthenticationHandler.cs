using System.Security.Claims;
using System.Text.Encodings.Web;
using EduNestIO.Common.Security;
using EduNestIO.WebServices.Business;
using Microsoft.AspNetCore.Authentication;
using Microsoft.Extensions.Options;

namespace EduNestIO.WebServices.RestAPI.Auth;

/// <summary>
/// Validates a bearer session token on each request by resolving it against the
/// database (core.fn_validate_session via AuthBL). On success it builds a
/// ClaimsPrincipal carrying user id, tenant id, roles and permission claims. The
/// tenant id therefore comes only from the server-validated session, never from the
/// client. This is the single server-side security boundary.
/// </summary>
public sealed class TokenAuthenticationHandler : AuthenticationHandler<AuthenticationSchemeOptions>
{
    public const string SchemeName = "EduNestToken";

    public TokenAuthenticationHandler(
        IOptionsMonitor<AuthenticationSchemeOptions> options,
        ILoggerFactory logger,
        UrlEncoder encoder)
        : base(options, logger, encoder)
    {
    }

    protected override Task<AuthenticateResult> HandleAuthenticateAsync()
    {
        if (!Request.Headers.TryGetValue("Authorization", out var authHeader))
        {
            return Task.FromResult(AuthenticateResult.NoResult());
        }

        var raw = authHeader.ToString();
        var token = raw.StartsWith("Bearer ", StringComparison.OrdinalIgnoreCase)
            ? raw["Bearer ".Length..].Trim()
            : raw.Trim();

        if (string.IsNullOrWhiteSpace(token))
        {
            return Task.FromResult(AuthenticateResult.Fail("Missing token"));
        }

        UserContext? ctx;
        try
        {
            ctx = new AuthBL().ValidateToken(token);
        }
        catch
        {
            return Task.FromResult(AuthenticateResult.Fail("Token validation error"));
        }

        if (ctx is null)
        {
            return Task.FromResult(AuthenticateResult.Fail("Invalid or expired token"));
        }

        var claims = new List<Claim>
        {
            new(ClaimTypes.NameIdentifier, ctx.UserId.ToString()),
            new(ClaimTypes.Name, ctx.Username),
            new("tenant_id", ctx.TenantId.ToString())
        };
        if (!string.IsNullOrEmpty(ctx.Email)) claims.Add(new Claim(ClaimTypes.Email, ctx.Email));
        if (ctx.StudentId.HasValue) claims.Add(new Claim("student_id", ctx.StudentId.Value.ToString()));
        claims.AddRange(ctx.Roles.Select(r => new Claim(ClaimTypes.Role, r)));
        claims.AddRange(ctx.Permissions.Select(p => new Claim("permission", p)));

        var identity = new ClaimsIdentity(claims, SchemeName);
        var principal = new ClaimsPrincipal(identity);
        var ticket = new AuthenticationTicket(principal, SchemeName);
        return Task.FromResult(AuthenticateResult.Success(ticket));
    }
}
