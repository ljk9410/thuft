const { onRequest } = require('firebase-functions/v2/https');
const axios = require('axios');
const querystring = require('querystring');

exports.exchangeCodeForTokenV2 = onRequest(
	{
		secrets: ['THREADS_APP_ID', 'THREADS_APP_SECRET'],
	},
	async (req, res) => {
		const code = req.query.code;
		console.log('Received code:', code);

		try {
			const clientId = process.env.THREADS_APP_ID;
			const clientSecret = process.env.THREADS_APP_SECRET;

			console.log('Using client ID:', clientId);
			console.log('Client ID type:', typeof clientId);
			console.log('Client ID length:', clientId.length);

			// 요청 데이터 준비
			const formData = querystring.stringify({
				client_id: clientId.toString().trim(),
				client_secret: clientSecret.toString().trim(),
				code: code,
				grant_type: 'authorization_code',
				redirect_uri: 'https://exchangecodefortokenv2-c6v7kntvaa-uc.a.run.app',
			});

			console.log('Request form data:', formData);

			const response = await axios({
				method: 'post',
				url: 'https://graph.threads.net/oauth/access_token',
				data: formData,
				headers: {
					'Content-Type': 'application/x-www-form-urlencoded',
					'Content-Length': formData.length,
					Accept: 'application/json',
				},
				maxRedirects: 0, // 리다이렉트 비활성화
			});

			console.log('Token exchange response:', {
				status: response.status,
				statusText: response.statusText,
				data: response.data,
				headers: response.headers,
			});

			if (!response.data.access_token) {
				throw new Error('Access token not found in response');
			}

			const redirectUrl = `thuft://callback?access_token=${response.data.access_token}&user_id=${response.data.user_id}`;
			console.log('Redirecting to:', redirectUrl);
			res.redirect(redirectUrl);
		} catch (error) {
			console.error('Token exchange error details:', {
				message: error.message,
				response: {
					data: error.response?.data,
					status: error.response?.status,
					headers: error.response?.headers,
					config: {
						url: error.response?.config?.url,
						method: error.response?.config?.method,
						headers: error.response?.config?.headers,
						data: error.response?.config?.data,
					},
				},
				stack: error.stack,
			});

			let errorMessage;
			if (error.response?.data?.error) {
				const errorData = error.response.data.error;
				errorMessage =
					typeof errorData === 'string'
						? errorData
						: errorData.message || errorData.type || 'Unknown error';
			} else {
				errorMessage = error.message;
			}

			const errorUrl = `thuft://callback?error=${encodeURIComponent(
				errorMessage
			)}`;
			console.log('Redirecting to error URL:', errorUrl);
			res.redirect(errorUrl);
		}
	}
);
