namespace EduNestIO.WebServices.RestAPI.Middleware;

/// <summary>Assigns/propagates X-Correlation-ID per request and exposes it on the response.</summary>
public sealed class CorrelationIdMiddleware
{
    public const string HeaderName = "X-Correlation-ID";
    private readonly RequestDelegate _next;

    public CorrelationIdMiddleware(RequestDelegate next) => _next = next;

    public async Task InvokeAsync(HttpContext context)
    {
        var id = context.Request.Headers.TryGetValue(HeaderName, out var h) && !string.IsNullOrWhiteSpace(h)
            ? h.ToString() : Guid.NewGuid().ToString("N");
        context.Items["CorrelationId"] = id;
        context.Response.Headers[HeaderName] = id;
        await _next(context);
    }
}
