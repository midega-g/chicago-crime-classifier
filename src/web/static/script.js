document.addEventListener('DOMContentLoaded', function() {
    const fileInput = document.getElementById('fileInput');
    const fileInfo = document.getElementById('fileInfo');
    const fileName = document.getElementById('fileName');
    const submitBtn = document.getElementById('submitBtn');
    const uploadForm = document.getElementById('uploadForm');
    const loading = document.getElementById('loading');

    // Handle file selection
    fileInput.addEventListener('change', function(e) {
        const file = e.target.files[0];

        if (file) {
            // Validate file type
            const fileName = file.name.toLowerCase();
            if (!fileName.endsWith('.csv') && !fileName.endsWith('.csv.gz')) {
                alert('Please select a CSV or gzipped CSV file.');
                fileInput.value = '';
                return;
            }

            // Show file info
            fileName.textContent = file.name;
            fileInfo.style.display = 'block';
            submitBtn.disabled = false;

            // Update file input label
            const label = document.querySelector('.file-input-label span');
            label.textContent = 'File Selected';

        } else {
            // Hide file info
            fileInfo.style.display = 'none';
            submitBtn.disabled = true;

            // Reset file input label
            const label = document.querySelector('.file-input-label span');
            label.textContent = 'Choose CSV File';
        }
    });

    // Handle form submission
    uploadForm.addEventListener('submit', function(e) {
        e.preventDefault();

        const file = fileInput.files[0];
        if (!file) {
            alert('Please select a file first.');
            return;
        }

        // Hide upload form and show loading animation
        uploadForm.style.display = 'none';
        document.querySelector('.upload-header').style.display = 'none';
        loading.style.display = 'block';

        // Simulate progress steps
        setTimeout(() => {
            document.getElementById('step2').classList.add('active');
        }, 1000);

        setTimeout(() => {
            document.getElementById('step3').classList.add('active');
        }, 2000);

        // Submit form
        const formData = new FormData();
        formData.append('file', file);

        fetch('/upload', {
            method: 'POST',
            body: formData
        })
        .then(response => response.text())
        .then(html => {
            // Replace current page with response
            document.body.innerHTML = html;
        })
        .catch(error => {
            console.error('Error:', error);
            alert('An error occurred while processing your file. Please try again.');

            // Hide loading and show upload form again
            loading.style.display = 'none';
            uploadForm.style.display = 'block';
            document.querySelector('.upload-header').style.display = 'block';
        });
    });

    // Drag and drop functionality
    const uploadCard = document.querySelector('.upload-card');
    const fileInputLabel = document.querySelector('.file-input-label');

    ['dragenter', 'dragover', 'dragleave', 'drop'].forEach(eventName => {
        uploadCard.addEventListener(eventName, preventDefaults, false);
    });

    function preventDefaults(e) {
        e.preventDefault();
        e.stopPropagation();
    }

    ['dragenter', 'dragover'].forEach(eventName => {
        uploadCard.addEventListener(eventName, highlight, false);
    });

    ['dragleave', 'drop'].forEach(eventName => {
        uploadCard.addEventListener(eventName, unhighlight, false);
    });

    function highlight(e) {
        fileInputLabel.style.borderColor = '#667eea';
        fileInputLabel.style.borderStyle = 'dashed';
        fileInputLabel.style.backgroundColor = 'rgba(102, 126, 234, 0.1)';
    }

    function unhighlight(e) {
        fileInputLabel.style.borderColor = 'transparent';
        fileInputLabel.style.backgroundColor = '';
    }

    uploadCard.addEventListener('drop', handleDrop, false);

    function handleDrop(e) {
        const dt = e.dataTransfer;
        const files = dt.files;

        if (files.length > 0) {
            fileInput.files = files;

            // Trigger change event
            const event = new Event('change', { bubbles: true });
            fileInput.dispatchEvent(event);
        }
    }
});
