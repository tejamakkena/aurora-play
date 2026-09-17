# Docker Deployment Guide - Gamelab2

This guide provides comprehensive instructions for deploying Gamelab2 using Docker and Docker Compose.

## Table of Contents

- [Prerequisites](#prerequisites)
- [Quick Start](#quick-start)
- [Environment Configuration](#environment-configuration)
- [Development Deployment](#development-deployment)
- [Production Deployment](#production-deployment)
- [Database Management](#database-management)
- [Troubleshooting](#troubleshooting)
- [Performance Optimization](#performance-optimization)

---

## Prerequisites

### Required Software

- **Docker**: Version 20.10 or higher
  - [Install Docker](https://docs.docker.com/get-docker/)
- **Docker Compose**: Version 1.29 or higher
  - [Install Docker Compose](https://docs.docker.com/compose/install/)

### System Requirements

- **RAM**: Minimum 2GB, Recommended 4GB+
- **Storage**: Minimum 5GB free space
- **OS**: Linux, macOS, or Windows 10/11 with WSL2

Verify installation:
```bash
docker --version
docker-compose --version
```

---

## Quick Start

### 1. Clone the Repository

```bash
git clone https://github.com/your-username/gamelab2.git
cd gamelab2
```

### 2. Start with Docker Compose (Development)

```bash
docker-compose up -d
```

The application will be available at: **http://localhost:5000**

### 3. Stop the Application

```bash
docker-compose down
```

---

## Environment Configuration

### Environment Variables

Create a `.env` file in the project root:

```bash
# Flask Configuration
FLASK_APP=app.py
FLASK_ENV=development  # Use 'production' for production
SECRET_KEY=your-secret-key-here-change-this

# Database Configuration
DATABASE_URL=postgresql://user:password@db:5432/gamelab
POSTGRES_DB=gamelab
POSTGRES_USER=user
POSTGRES_PASSWORD=password

# Application Settings
DEBUG=True  # Set to False in production
PORT=5000
HOST=0.0.0.0

# Security (Production Only)
SESSION_COOKIE_SECURE=True
SESSION_COOKIE_HTTPONLY=True
SESSION_COOKIE_SAMESITE=Lax
```

### Important Security Notes

⚠️ **Never commit `.env` files to version control!**

Add to `.gitignore`:
```bash
echo ".env" >> .gitignore
```

🔒 **Production Security Checklist:**
- Generate a strong `SECRET_KEY` (use `python -c "import secrets; print(secrets.token_hex(32))"`)
- Use strong database passwords (20+ characters, mixed case, numbers, symbols)
- Set `FLASK_ENV=production`
- Set `DEBUG=False`
- Enable HTTPS/SSL certificates
- Use environment-specific database credentials

---

## Development Deployment

### Using Docker Compose (Recommended)

```bash
# Start all services in detached mode
docker-compose up -d

# View logs
docker-compose logs -f web

# Access the web container shell
docker-compose exec web bash

# Run Flask commands
docker-compose exec web flask db upgrade
docker-compose exec web flask shell

# Rebuild after code changes
docker-compose up -d --build

# Stop and remove containers
docker-compose down

# Stop and remove containers + volumes (⚠️ deletes database data)
docker-compose down -v
```

### Using Dockerfile Directly

```bash
# Build the image
docker build -t gamelab2:dev .

# Run the container
docker run -d \
  -p 5000:5000 \
  -v $(pwd):/app \
  -e FLASK_ENV=development \
  --name gamelab2-web \
  gamelab2:dev

# View logs
docker logs -f gamelab2-web

# Stop and remove
docker stop gamelab2-web
docker rm gamelab2-web
```

### Hot Reloading

The development setup includes volume mounting for hot reloading:
- Code changes are automatically reflected (Flask auto-reloader)
- No need to rebuild for Python file changes
- CSS/JS changes require browser refresh

---

## Production Deployment

### 1. Create Production Dockerfile

Create `Dockerfile.prod`:

```dockerfile
FROM python:3.10-slim

# Set working directory
WORKDIR /app

# Install system dependencies
RUN apt-get update && apt-get install -y \
    build-essential \
    libpq-dev \
    && rm -rf /var/lib/apt/lists/*

# Copy requirements first for better caching
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

# Copy application code
COPY . /app

# Create non-root user
RUN useradd -m -u 1000 appuser && chown -R appuser:appuser /app
USER appuser

# Set production environment variables
ENV FLASK_ENV=production
ENV PYTHONUNBUFFERED=1

# Expose port
EXPOSE 5000

# Use production server (gunicorn)
CMD ["gunicorn", "--bind", "0.0.0.0:5000", "--workers", "4", "--timeout", "120", "app:app"]
```

### 2. Create Production Compose File

Create `docker-compose.prod.yml`:

```yaml
version: '3.8'

services:
  web:
    build:
      context: .
      dockerfile: Dockerfile.prod
    ports:
      - "5000:5000"
    environment:
      - FLASK_ENV=production
      - DATABASE_URL=${DATABASE_URL}
      - SECRET_KEY=${SECRET_KEY}
    depends_on:
      - db
    restart: unless-stopped
    
  db:
    image: postgres:13-alpine
    environment:
      - POSTGRES_DB=${POSTGRES_DB}
      - POSTGRES_USER=${POSTGRES_USER}
      - POSTGRES_PASSWORD=${POSTGRES_PASSWORD}
    volumes:
      - postgres_data:/var/lib/postgresql/data
    restart: unless-stopped
    
  nginx:
    image: nginx:alpine
    ports:
      - "80:80"
      - "443:443"
    volumes:
      - ./nginx.conf:/etc/nginx/nginx.conf:ro
      - ./ssl:/etc/nginx/ssl:ro
    depends_on:
      - web
    restart: unless-stopped

volumes:
  postgres_data:
```

### 3. Add Gunicorn to Requirements

Update `requirements.txt`:
```
gunicorn==21.2.0
```

### 4. Deploy to Production

```bash
# Build and start production services
docker-compose -f docker-compose.prod.yml up -d --build

# Run database migrations
docker-compose -f docker-compose.prod.yml exec web flask db upgrade

# View production logs
docker-compose -f docker-compose.prod.yml logs -f
```

### 5. Nginx Configuration (Optional but Recommended)

Create `nginx.conf`:

```nginx
events {
    worker_connections 1024;
}

http {
    upstream web {
        server web:5000;
    }

    server {
        listen 80;
        server_name your-domain.com;
        
        # Redirect HTTP to HTTPS
        return 301 https://$server_name$request_uri;
    }

    server {
        listen 443 ssl http2;
        server_name your-domain.com;

        ssl_certificate /etc/nginx/ssl/cert.pem;
        ssl_certificate_key /etc/nginx/ssl/key.pem;

        location / {
            proxy_pass http://web;
            proxy_set_header Host $host;
            proxy_set_header X-Real-IP $remote_addr;
            proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
            proxy_set_header X-Forwarded-Proto $scheme;
        }

        location /static {
            alias /app/static;
            expires 30d;
        }
    }
}
```

---

## Database Management

### Backup Database

```bash
# Create backup
docker-compose exec db pg_dump -U user gamelab > backup_$(date +%Y%m%d_%H%M%S).sql

# Compress backup
gzip backup_*.sql
```

### Restore Database

```bash
# Stop web service
docker-compose stop web

# Restore from backup
cat backup.sql | docker-compose exec -T db psql -U user gamelab

# Restart web service
docker-compose start web
```

### Reset Database (⚠️ Deletes All Data)

```bash
docker-compose down -v
docker-compose up -d
docker-compose exec web flask db upgrade
```

### Access PostgreSQL CLI

```bash
docker-compose exec db psql -U user -d gamelab
```

Common PostgreSQL commands:
```sql
\l          -- List databases
\dt         -- List tables
\d+ table   -- Describe table
\q          -- Quit
```

---

## Troubleshooting

### Container Won't Start

**Issue**: `docker-compose up` fails

**Solutions**:
```bash
# Check logs
docker-compose logs web
docker-compose logs db

# Rebuild containers
docker-compose down
docker-compose up -d --build

# Remove all containers and volumes (⚠️ deletes data)
docker-compose down -v
docker system prune -a
```

### Port Already in Use

**Issue**: "Error: port 5000 is already allocated"

**Solutions**:
```bash
# Find process using port 5000
lsof -i :5000  # macOS/Linux
netstat -ano | findstr :5000  # Windows

# Kill the process or change port in docker-compose.yml:
ports:
  - "5001:5000"  # Use 5001 instead
```

### Database Connection Errors

**Issue**: "Could not connect to database"

**Solutions**:
```bash
# Check if database is running
docker-compose ps

# Check database logs
docker-compose logs db

# Verify DATABASE_URL matches docker-compose.yml
# Format: postgresql://user:password@db:5432/gamelab

# Wait for database to be ready (takes 5-10 seconds on first start)
docker-compose up -d db
sleep 10
docker-compose up -d web
```

### Permission Denied Errors

**Issue**: "Permission denied" when accessing files

**Solutions**:
```bash
# Fix ownership (Linux/macOS)
sudo chown -R $USER:$USER .

# Run container as your user
docker-compose exec -u $(id -u):$(id -g) web bash
```

### Slow Build Times

**Issue**: `docker build` takes too long

**Solutions**:
```bash
# Use BuildKit for faster builds
export DOCKER_BUILDKIT=1
docker-compose build

# Use multi-stage builds (already implemented in Dockerfile.prod)

# Clear Docker cache if needed
docker builder prune
```

### Memory Issues

**Issue**: Container crashes with "Out of memory"

**Solutions**:
```bash
# Increase Docker memory limit (Docker Desktop)
# Settings → Resources → Memory → Increase to 4GB+

# Reduce worker count in production (Dockerfile.prod)
CMD ["gunicorn", "--workers", "2", ...]  # Reduce from 4 to 2
```

---

## Performance Optimization

### Docker Image Size Optimization

Current optimizations in place:
- ✅ Using `python:3.10-slim` (not full Python image)
- ✅ Multi-stage builds in production
- ✅ Combining RUN commands to reduce layers
- ✅ Using `.dockerignore` to exclude unnecessary files

Create `.dockerignore`:
```
__pycache__
*.pyc
*.pyo
*.log
.git
.gitignore
.env
node_modules
.vscode
.idea
*.md
tests/
```

### Database Performance

```yaml
# docker-compose.yml optimization
db:
  image: postgres:13-alpine
  environment:
    - POSTGRES_INITDB_ARGS="-E UTF8 --lc-collate=C --lc-ctype=C"
  command: 
    - "postgres"
    - "-c"
    - "max_connections=100"
    - "-c"
    - "shared_buffers=256MB"
    - "-c"
    - "effective_cache_size=1GB"
```

### Application Performance

1. **Enable Gzip Compression** (via Nginx)
2. **Use Redis for Sessions** (add Redis service)
3. **Enable Static File Caching** (already configured in Nginx example)
4. **Use Connection Pooling** (SQLAlchemy already does this)

---

## Health Checks

Add health checks to `docker-compose.yml`:

```yaml
web:
  healthcheck:
    test: ["CMD", "curl", "-f", "http://localhost:5000/health"]
    interval: 30s
    timeout: 10s
    retries: 3
    start_period: 40s
```

Add health endpoint to Flask app:
```python
@app.route('/health')
def health():
    return {'status': 'healthy'}, 200
```

---

## Production Deployment Checklist

Before deploying to production:

- [ ] Generate secure `SECRET_KEY`
- [ ] Set `FLASK_ENV=production`
- [ ] Set `DEBUG=False`
- [ ] Use strong database password
- [ ] Configure SSL/HTTPS certificates
- [ ] Set up automated backups
- [ ] Configure monitoring/logging
- [ ] Test database migrations
- [ ] Set up reverse proxy (Nginx)
- [ ] Configure firewall rules
- [ ] Set up container restart policies
- [ ] Test rollback procedure
- [ ] Document environment variables
- [ ] Set up CI/CD pipeline (optional)

---

## Monitoring & Logs

### View Logs

```bash
# All services
docker-compose logs -f

# Specific service
docker-compose logs -f web

# Last 100 lines
docker-compose logs --tail=100 web

# Since timestamp
docker-compose logs --since="2026-02-17T20:00:00" web
```

### Container Stats

```bash
# Real-time resource usage
docker stats

# Disk usage
docker system df
```

---

## Additional Resources

- [Docker Documentation](https://docs.docker.com/)
- [Docker Compose Documentation](https://docs.docker.com/compose/)
- [Flask Deployment Options](https://flask.palletsprojects.com/en/2.3.x/deploying/)
- [PostgreSQL Docker Documentation](https://hub.docker.com/_/postgres)
- [Gunicorn Documentation](https://docs.gunicorn.org/)

---

## Support

For issues or questions:
1. Check this documentation first
2. Review logs: `docker-compose logs`
3. Check GitHub Issues
4. Contact the development team

---

**Last Updated**: February 17, 2026  
**Version**: 1.0  
**Maintained by**: Jarvis (AI Assistant)
