using EduNestIO.Common;
using EduNestIO.Common.Logging;
using EduNestIO.WebServices.Business;
using EduNestIO.WebServices.RestAPI.Auth;
using EduNestIO.WebServices.RestAPI.Filters;
using EduNestIO.WebServices.RestAPI.Middleware;
using Microsoft.AspNetCore.Authentication;
using Microsoft.OpenApi.Models;

namespace EduNestIO.WebServices.RestAPI;

/// <summary>
/// Startup wiring, following the reference project's Startup/Program split and
/// config/appsettings.json loading. Registers the token auth scheme, Newtonsoft
/// JSON, CORS, Swagger and the centralized exception filter.
/// </summary>
public class Startup
{
    public IConfiguration Configuration { get; }
    private IConfigurationRoot ConfigurationRoot { get; }
    private readonly IHostEnvironment _env;

    public Startup(IConfiguration configuration, IHostEnvironment env)
    {
        Configuration = configuration;
        _env = env;

        // Load configuration from config/appsettings.json, then the environment-specific
        // overlay (e.g. appsettings.Development.json — git-ignored, holds local secrets
        // like the DB password), then environment variables (which win over both).
        var builder = new ConfigurationBuilder()
            .SetBasePath(Path.Combine(_env.ContentRootPath, "config"))
            .AddJsonFile("appsettings.json", optional: false, reloadOnChange: true)
            .AddJsonFile($"appsettings.{_env.EnvironmentName}.json", optional: true, reloadOnChange: true)
            .AddEnvironmentVariables();
        ConfigurationRoot = builder.Build();

        AppConfig.LoadParameters(ConfigurationRoot);
        LogWriter.Configure(AppConfig.LogDirectory, LoggingLevel.Detail);

        // Npgsql legacy switches for timestamptz behaviour (as in reference).
        AppContext.SetSwitch("Npgsql.EnableLegacyTimestampBehavior", true);
    }

    public void ConfigureServices(IServiceCollection services)
    {
        services.AddSingleton<IConfigurationRoot>(ConfigurationRoot);
        services.AddHttpContextAccessor();

        services.AddControllers(options =>
        {
            options.Filters.Add<ServiceExceptionFilter>();
        }).AddNewtonsoftJson(o =>
        {
            o.SerializerSettings.DateFormatString = "yyyy-MM-ddTHH:mm:ss.fff";
        });

        services.Configure<Microsoft.AspNetCore.Mvc.ApiBehaviorOptions>(o =>
        {
            o.SuppressModelStateInvalidFilter = true;
        });

        services.AddCors(cors => cors.AddDefaultPolicy(policy =>
        {
            var origins = ConfigurationRoot.GetSection("Cors:AllowedOrigins").Get<string[]>()
                          ?? new[] { "http://localhost:4200" };
            policy.WithOrigins(origins).AllowAnyHeader().AllowAnyMethod();
        }));

        services.AddAuthentication(TokenAuthenticationHandler.SchemeName)
            .AddScheme<AuthenticationSchemeOptions, TokenAuthenticationHandler>(
                TokenAuthenticationHandler.SchemeName, null);
        services.AddAuthorization();

        services.AddEndpointsApiExplorer();
        services.AddSwaggerGen(c =>
        {
            c.SwaggerDoc("v1", new OpenApiInfo { Title = "EduNestIO API", Version = "v1" });
            var scheme = new OpenApiSecurityScheme
            {
                Name = "Authorization",
                Type = SecuritySchemeType.Http,
                Scheme = "bearer",
                BearerFormat = "Token",
                In = ParameterLocation.Header,
                Reference = new OpenApiReference { Type = ReferenceType.SecurityScheme, Id = "Bearer" }
            };
            c.AddSecurityDefinition("Bearer", scheme);
            c.AddSecurityRequirement(new OpenApiSecurityRequirement { [scheme] = Array.Empty<string>() });
        });
    }

    public void Configure(IApplicationBuilder app, IWebHostEnvironment env)
    {
        AppContext.SetSwitch("Npgsql.EnableLegacyTimestampBehavior", true);

        app.UseMiddleware<CorrelationIdMiddleware>();

        if (env.IsDevelopment())
        {
            app.UseSwagger();
            app.UseSwaggerUI(c => c.SwaggerEndpoint("/swagger/v1/swagger.json", "EduNestIO API"));
        }

        app.UseRouting();
        app.UseCors();
        app.UseAuthentication();
        app.UseAuthorization();

        app.UseEndpoints(endpoints => endpoints.MapControllers());

        // Development-only demo seeding (idempotent, password from config/env).
        var seedEnabled = ConfigurationRoot.GetValue<bool>("Seed:Enabled");
        if (env.IsDevelopment() && seedEnabled)
        {
            try
            {
                var pw = ConfigurationRoot["Seed:DemoUserPassword"] ?? "";
                new DevSeedBL().SeedDemoUsers(pw);
            }
            catch (Exception ex)
            {
                LogWriter.WriteLog(new LogDTO
                {
                    FunctionName = "Configure", ClassName = nameof(Startup),
                    LogStringLevel = LoggingLevel.Exceptional, ExceptionString = ex.Message,
                    Message = "Demo seeding failed (non-fatal)."
                });
            }
        }
    }
}
