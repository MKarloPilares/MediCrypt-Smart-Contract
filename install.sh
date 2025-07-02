# Install Rust and Cargo
curl https://sh.rustup.rs -sSf | sh -s -- -y

source "$HOME/.cargo/env"

# Install cargo-stylus
RUSTFLAGS="-C link-args=-rdynamic" cargo install --force cargo-stylus
rustup target add wasm32-unknown-unknown

# Test cargo-stylus
# cargo stylus --help