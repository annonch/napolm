# Use Red Hat Universal Base Image Micro as the base
FROM debian:bookworm-slim

# Set environment variables
ENV HOME=/home/emacs \
    SCRIPT_DIR=/scripts

RUN apt-get update -y && apt-get install -y emacs curl
RUN emacs --version

# Create directories for scripts
RUN mkdir -p $SCRIPT_DIR
WORKDIR $SCRIPT_DIR

# Copy Emacs Lisp files into the container
COPY *.el $SCRIPT_DIR/

# Optional: set executable permissions
RUN chmod +x *.el

EXPOSE 4222
# Run an Emacs Lisp file non-interactively as the container startup
CMD ["emacs", "--script", "main.el"]
