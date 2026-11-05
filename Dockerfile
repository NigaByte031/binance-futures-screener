FROM python:3.12-alpine

LABEL org.opencontainers.image.title="Binance Futures Screener" \
      org.opencontainers.image.description="Binance USDT-M futures coins sorted by 2h/6h/12h/24h change" \
      org.opencontainers.image.source="https://github.com/NigaByte031/binance-futures-screener" \
      org.opencontainers.image.licenses="MIT"

WORKDIR /app
COPY index.html server.py ./

ENV PORT=8080 \
    BIND=0.0.0.0 \
    PYTHONUNBUFFERED=1

EXPOSE 8080

HEALTHCHECK --interval=30s --timeout=3s --start-period=5s --retries=3 \
  CMD python3 -c "import urllib.request,os;urllib.request.urlopen('http://127.0.0.1:'+os.environ.get('PORT','8080')+'/healthz').read()"

USER nobody
CMD ["python3", "server.py"]
