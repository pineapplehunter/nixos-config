{ prev, ... }: {
  curl-http3 = prev.curl.override {
    http3Support = true;
    openssl = prev.quictls;
  };
}
